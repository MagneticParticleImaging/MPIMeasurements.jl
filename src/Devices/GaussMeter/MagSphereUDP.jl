export MagSphereUDP, MagSphereUDPParams, MagSphereUDPResult

#=
MagSphereUDP: driver for the PHYMAG MagSphere with 114 sensors
(manual v1.0, 24.08.2026). Lives next to the serial `MagSphere` driver.

How the parts fit together
  Setup        TOML -> MagSphereUDPParams -> _init -> configure! -> sendCommand -> sphere, UDP 1234
  Streaming    enable -> reader task (readData) -> parseFrame -> _publish! -> channel + newest frame
  Reading      take!             every frame in order, from the channel
               getXYZValues      next fresh frame (acquireFrame), with or without a running stream
  Shutdown     disable / close

Trigger modes (Sect. 1.3 and Table 2 of the manual)
  internal   free running on the sphere's clock. `start` / `stop` switch the
             stream on and off, so enable, disable and direct reads send them.
  external   one frame per edge at the BNC input (`oneshot_on` + `trigger`).
             The trigger signal alone decides when frames come; `start` and
             `stop` are never sent in this mode.

Threads and locks
  - Only one piece of code reads the data port at a time: the reader task while
    the stream runs, otherwise _readDirect while holding `cam.lock`.
  - `cam.lock`       enable, disable, configure! and direct reads
  - `cam.cmdLock`    one command at a time on the command socket
  - `cam.latestLock` newest frame, frame and drop counters

Wire format, confirmed with magsphere_probe.jl on the real device
  Frame, 2066 bytes, one UDP broadcast to 192.168.1.255:65534
    bytes 1-8     timestamp, UInt64 big-endian, µs on the sphere clock (the manual
                  says Unix time, the vendor's udp.jl CLOCK_MONOTONIC_RAW; only
                  differences between frames are meaningful either way)
    bytes 9-12    hub temperature, Float32 little-endian, °C
    byte  13      0xAB
    bytes 14-2065 114 sensor packets of 18 bytes, in sensor-ID order (Table 5)
    byte  2066    0xBA
  Sensor packet, 18 bytes (offsets from the packet start)
    0-1    0xAA 0x55
    2      ID on its board: (Bus - 1) * 4 + Sensor from Table 5, so 1..8
    3-14   X, Y, Z as Float32 little-endian, calibrated, in µT
    15-16  sensor temperature, UInt16 little-endian, °C × 10
    17     XOR of bytes 0-16
  The manual's sum checksum and uint32 hub temperature are wrong; udp.jl is right.

Needs the Sockets standard library in the package's Project.toml and Unitful
in scope, as for the other drivers.
=#
import Sockets

# --- Constants -------------------------------------------------------------

const MAGSPHERE_UDP_NUM_SENSORS = 114
const MAGSPHERE_UDP_PACKET_SIZE = 18
const MAGSPHERE_UDP_HEADER_SIZE = 12     # timestamp + hub temperature
const MAGSPHERE_UDP_FRAME_SIZE = MAGSPHERE_UDP_HEADER_SIZE + 1 +
  MAGSPHERE_UDP_NUM_SENSORS * MAGSPHERE_UDP_PACKET_SIZE + 1   # 2066 bytes
const MAGSPHERE_UDP_COMMAND_DELAY = 0.05 # s, pause after each command so the sphere keeps up

# Command strings exactly as in Table 2 of the manual, underscores included.
const MAGSPHERE_UDP_RATE_COMMANDS = Dict(1 => "1rate", 10 => "10rate", 100 => "100rate", 1000 => "1krate")
const MAGSPHERE_UDP_RANGE_COMMANDS = Dict(120 => "low_measure_", 240 => "high_measure")
const MAGSPHERE_UDP_TRIGGER_COMMANDS = Dict(
  "internal" => ["trigger0", "oneshot_off"],  # free running on the internal clock
  "external" => ["oneshot_on", "trigger"],    # one frame per BNC edge (not yet tested)
)

# --- Types -----------------------------------------------------------------

"""
Parameters of a `MagSphereUDP`, read from the device entry of the TOML file.
The acquisition settings are sent to the sphere in `_init` and can be changed
later with `configure!`.
"""
Base.@kwdef struct MagSphereUDPParams <: DeviceParams
  # Network
  deviceIP::String = "192.168.1.1"      # address of the sphere, commands go here
  listenIP::String = "0.0.0.0"          # local address of the data port, keep 0.0.0.0 (see _openDataSocket)
  dataPort::Int64 = 65534               # port the sphere broadcasts frames to
  commandPort::Int64 = 1234             # port the sphere takes commands on
  # Acquisition
  samplingRate::typeof(1.0u"Hz") = 100.0u"Hz"      # 1, 10, 100 or 1000 Hz, internal trigger only
  measurementRange::typeof(1.0u"mT") = 120.0u"mT"  # ±120 mT or ±240 mT
  triggerMode::String = "internal"                 # "internal" or "external" (BNC)
  # Driver behaviour
  bufferSize::Int64 = 2048              # frames in the channel before the oldest is dropped
  timeout::typeof(1.0u"s") = 2.0u"s"    # longest wait for one frame in getXYZValues
  verifySensorIds::Bool = true          # check each packet's ID byte against Table 5
  checkOnInit::Bool = true              # read one frame in _init to check the network link
end
MagSphereUDPParams(dict::Dict) = params_from_dict(MagSphereUDPParams, dict)

"""
One measurement of all 114 sensors.

- `timestamp`: sphere clock in µs. Use differences between frames; the
  absolute value depends on the sphere's system time (set in the Web GUI).
- `received`: PC arrival time, `time()` in s.
- `hubTemperature`: °C, temperature in the centre of the sphere.
- `data`: 3×114 field in Tesla, column s = sensor ID s, NaN for invalid sensors.
- `sensorTemperature`: °C per sensor, NaN for invalid sensors.
- `valid`: start marker, checksum and (optionally) sensor ID were correct.
"""
struct MagSphereUDPResult
  timestamp::UInt64
  received::Float64
  hubTemperature::Float64
  data::Matrix{typeof(1.0u"T")}
  sensorTemperature::Vector{Float64}
  valid::BitVector
end

"""
Device object for the MagSphere. Created by the framework from the TOML entry;
`_init` opens the command socket and configures the sphere.
"""
Base.@kwdef mutable struct MagSphereUDP <: GaussMeter
  @add_device_fields MagSphereUDPParams

  # Network
  deviceAddr::Union{Nothing, Sockets.IPv4} = nothing
  cmdSocket::Union{Nothing, Sockets.UDPSocket} = nothing
  dataSocket::Union{Nothing, Sockets.UDPSocket} = nothing   # only while the stream runs

  # Settings last sent to the sphere; it does not acknowledge commands
  samplingRate::typeof(1.0u"Hz") = 0.0u"Hz"
  measurementRange::typeof(1.0u"mT") = 0.0u"mT"
  triggerMode::String = ""

  # Stream
  ch::Channel{MagSphereUDPResult} = Channel{MagSphereUDPResult}(1)
  task::Union{Nothing, Task} = nothing
  lock::ReentrantLock = ReentrantLock()
  cmdLock::ReentrantLock = ReentrantLock()

  # Newest frame, so getXYZValues can wait for a fresh one without consuming
  # (and stealing) frames from the channel
  latestLock::ReentrantLock = ReentrantLock()
  latest::Union{Nothing, MagSphereUDPResult} = nothing
  frameCount::Int = 0
  droppedFrames::Int = 0      # malformed datagrams
  overflowFrames::Int = 0     # good frames pushed out of the full channel
  warnedSensors::BitVector = falses(MAGSPHERE_UDP_NUM_SENSORS)
end

neededDependencies(::MagSphereUDP) = []
optionalDependencies(::MagSphereUDP) = []

# --- Setup and configuration -----------------------------------------------

"""
    _init(cam::MagSphereUDP)

Called once by the framework when the device is created. Opens the command
socket, sends the acquisition settings from the params via `configure!` and,
if `checkOnInit` is set, reads one frame to check that data arrive. With the
internal trigger it then sends `stop`, because the sphere starts streaming on
its own after boot. With the external trigger nothing more is needed:
`oneshot_on` already ends free running, and frames come only on BNC edges.
"""
function _init(cam::MagSphereUDP)
  p = cam.params
  cam.deviceAddr = parse(Sockets.IPv4, p.deviceIP)
  sock = Sockets.UDPSocket()
  bind(sock, Sockets.IPv4(0), 0) || error("MagSphereUDP: could not open the command socket.")
  cam.cmdSocket = sock

  configure!(cam; triggerMode = p.triggerMode, samplingRate = p.samplingRate,
                  measurementRange = p.measurementRange)
  _freeRunning(cam) && sendCommand(cam, "stop")
  @info "MagSphereUDP configured." p.deviceIP cam.samplingRate cam.measurementRange cam.triggerMode

  # With an external trigger there are no frames until the BNC input fires
  if p.checkOnInit && cam.triggerMode == "internal"
    frame = acquireFrame(cam)
    if isnothing(frame)
      @warn "MagSphereUDP: no usable frame on $(p.listenIP):$(p.dataPort) within $(p.timeout) " *
            "($(cam.droppedFrames) malformed). Check the RNDIS network adapter and the firewall."
    else
      @info "MagSphereUDP: receiving data, $(count(frame.valid)) of $(MAGSPHERE_UDP_NUM_SENSORS) sensors valid."
    end
  end
end

"""
    configure!(cam::MagSphereUDP; triggerMode, samplingRate, measurementRange)

Change the acquisition settings of the sphere. Keywords you leave out keep
their current value; numbers without units are read as Hz and mT.

    configure!(cam; measurementRange = 240u"mT")       # larger range, coarser resolution
    configure!(cam; triggerMode = "external")          # one frame per BNC edge
    configure!(cam; triggerMode = "internal", samplingRate = 1u"kHz")

All values are checked before the first command is sent, so a typo never
leaves the sphere half-configured. The trigger-mode commands go last, so no
rate or range command can follow (and possibly undo) the switch to the BNC
trigger. Works while the stream runs; frames already in the channel were taken
with the old settings. Changing the trigger mode while the stream runs leaves
`start`/`stop` bookkeeping to you; call `enable` again instead.
"""
function configure!(cam::MagSphereUDP; triggerMode = nothing, samplingRate = nothing,
                    measurementRange = nothing)
  cmds = String[]
  rate = isnothing(samplingRate) ? nothing : _strip(u"Hz", samplingRate)
  rangeMT = isnothing(measurementRange) ? nothing : _strip(u"mT", measurementRange)
  isnothing(rate) || push!(cmds, _lookup(MAGSPHERE_UDP_RATE_COMMANDS, rate, "samplingRate", "Hz"))
  isnothing(rangeMT) || push!(cmds, _lookup(MAGSPHERE_UDP_RANGE_COMMANDS, rangeMT, "measurementRange", "mT"))
  if !isnothing(triggerMode)
    haskey(MAGSPHERE_UDP_TRIGGER_COMMANDS, triggerMode) ||
      error("MagSphereUDP: triggerMode must be \"internal\" or \"external\", got \"$triggerMode\".")
    append!(cmds, MAGSPHERE_UDP_TRIGGER_COMMANDS[triggerMode])
  end

  lock(cam.lock) do        # don't interleave with the start/stop of a direct read
    foreach(cmd -> sendCommand(cam, cmd), cmds)
    isnothing(triggerMode) || (cam.triggerMode = triggerMode)
    isnothing(rate) || (cam.samplingRate = rate * u"Hz")
    isnothing(rangeMT) || (cam.measurementRange = rangeMT * u"mT")
  end
  return nothing
end

"""
    sendCommand(cam::MagSphereUDP, cmd)

Send one ASCII command from Table 2 of the manual to the sphere, e.g.
`sendCommand(cam, "ledon3")`. All other functions talk to the sphere through
this one. The sphere does not answer, so success is not confirmed.
"""
function sendCommand(cam::MagSphereUDP, cmd::AbstractString)
  lock(cam.cmdLock) do
    isnothing(cam.cmdSocket) && error("MagSphereUDP is not initialized.")
    Sockets.send(cam.cmdSocket, cam.deviceAddr, cam.params.commandPort, cmd)
    sleep(MAGSPHERE_UDP_COMMAND_DELAY)
  end
  return nothing
end

"""
    _trySend(cam, cmd)

`sendCommand` that logs failures instead of throwing. Used on shutdown paths
(`disable`, the end of a direct read), where an error must not prevent the
sockets from being closed.
"""
function _trySend(cam::MagSphereUDP, cmd::AbstractString)
  try
    sendCommand(cam, cmd)
  catch e
    @warn "MagSphereUDP: could not send \"$cmd\"." exception = e
  end
end

"""
    _lookup(table, value, name, unit)

Translate a setting such as 100 Hz into its command string (`"100rate"`), or
throw an error listing the allowed values.
"""
function _lookup(table::Dict{Int, String}, value::Real, name, unit)
  key = round(Int, value)
  (isapprox(value, key) && haskey(table, key)) ||
    error("MagSphereUDP: $name must be one of $(sort(collect(keys(table)))) $unit, got $value $unit.")
  return table[key]
end

"""
    _strip(unit, x)

Number in `unit` as Float64. Plain numbers are taken to be in `unit` already,
so `_strip(u"Hz", 1u"kHz") == _strip(u"Hz", 1000) == 1000.0`.
"""
_strip(unit, x::Real) = Float64(x)
_strip(unit, x::Unitful.Quantity) = Float64(ustrip(unit, x))

"""
    _freeRunning(cam)

True for the internal trigger, the only mode in which the sphere needs `start`
and `stop`. With the external trigger the BNC edges alone produce frames.
"""
_freeRunning(cam::MagSphereUDP) = cam.triggerMode == "internal"

"""
    _openDataSocket(params)

Open and bind a UDP socket on the data port. Binds to 0.0.0.0 by default
because on Linux a socket bound to one interface address does not receive
broadcasts to 192.168.1.255. `reuseaddr` lets the vendor tools listen at the
same time. Each stream and each direct read gets its own socket, so frames
buffered while nobody listened are never mistaken for fresh ones.
"""
function _openDataSocket(p::MagSphereUDPParams)
  sock = Sockets.UDPSocket()
  if !bind(sock, parse(Sockets.IPv4, p.listenIP), p.dataPort; reuseaddr = true)
    close(sock)
    error("MagSphereUDP: could not bind UDP port $(p.dataPort) on $(p.listenIP).")
  end
  return sock
end

# --- Streaming -------------------------------------------------------------

"""
    isrunning(cam::MagSphereUDP)

True while the reader task started by `enable` is alive.
"""
isrunning(cam::MagSphereUDP) = !isnothing(cam.task) && !istaskdone(cam.task)

"""
    _frameCount(cam)

Number of frames published since the device was created, read under
`latestLock`. `acquireFrame` compares it before and after waiting to know that
a frame is new.
"""
_frameCount(cam::MagSphereUDP) = lock(() -> cam.frameCount, cam.latestLock)

"""
    take!(cam::MagSphereUDP)

Next frame from the stream channel, as a `MagSphereUDPResult`. Use it to record
every frame in order while the stream runs. Non-blocking: throws if the channel
is empty. Assumes a single consumer.
"""
take!(cam::MagSphereUDP) = isready(cam.ch) ? take!(cam.ch) : error("Empty channel")

"""
    enable(cam::MagSphereUDP)

Start continuous acquisition: open a fresh data socket and channel, start the
reader task (`readData`) and, with the internal trigger, send `start` to the
sphere. With the external trigger nothing is sent; frames arrive as soon as
the BNC input sees edges. Stops a running stream first. Frames then arrive in
the channel (`take!`) and as the newest frame (`getXYZValues`).
"""
function enable(cam::MagSphereUDP)
  lock(cam.lock) do
    disable(cam)
    lock(cam.latestLock) do
      cam.latest = nothing
      cam.droppedFrames = 0
      cam.overflowFrames = 0
    end
    fill!(cam.warnedSensors, false)

    sock = _openDataSocket(cam.params)   # bind before "start" / the first trigger so no frame is missed
    ch = Channel{MagSphereUDPResult}(cam.params.bufferSize)
    cam.dataSocket = sock
    cam.ch = ch
    # Pass channel and socket explicitly so the task never sees later reassignments
    cam.task = Threads.@spawn readData(cam, ch, sock)
    bind(ch, cam.task)                    # channel closes if the task dies
    _freeRunning(cam) && sendCommand(cam, "start")
  end
end

"""
    disable(cam::MagSphereUDP)

Stop continuous acquisition: send `stop` (internal trigger only), close the
channel and the data socket (which wakes the reader task out of `recv`) and
wait up to 2 s for the task to end. Frames still in the channel stay readable
with `take!`. Safe to call when nothing is running.
"""
function disable(cam::MagSphereUDP)
  lock(cam.lock) do
    !isnothing(cam.cmdSocket) && _freeRunning(cam) && _trySend(cam, "stop")
    close(cam.ch)

    sock = cam.dataSocket
    cam.dataSocket = nothing
    isnothing(sock) || close(sock)

    task = cam.task
    cam.task = nothing
    isnothing(task) && return
    if timedwait(() -> istaskdone(task), 2.0; pollint = 0.01) !== :ok
      @warn "MagSphereUDP: reader task did not stop within 2 s."
      return
    end
    try
      wait(task)
    catch e
      @error "MagSphereUDP reader task failed" exception = (e, catch_backtrace())
    end
  end
end

"""
    readData(cam, ch, sock)

Body of the reader task started by `enable`. Receives datagrams, parses them
with `parseFrame` and hands good frames to `_publish!`. Ends when `disable`
closes the channel and the socket, or when receiving fails. While it runs it
is the only code reading the data port.
"""
function readData(cam::MagSphereUDP, ch::Channel{MagSphereUDPResult}, sock::Sockets.UDPSocket)
  while isopen(ch)
    bytes = try
      Sockets.recv(sock)
    catch e
      isopen(ch) || break                # disable() closed the socket to stop us
      @error "MagSphereUDP: receiving failed, reader stops." exception = e
      break
    end
    result = parseFrame(cam, bytes, time())
    if isnothing(result)
      _countDropped(cam, length(bytes))
      continue
    end
    _warnInvalidSensors(cam, result)
    _publish!(cam, ch, result) || break
  end
end

"""
    _publish!(cam, ch, result) -> Bool

Make a parsed frame available: store it as the newest frame (for
`acquireFrame`) and append it to the channel (for `take!`). When the channel is
full the oldest frame is dropped and counted in `overflowFrames`, so the reader
never stalls and the newest frame stays current. Returns false once the
channel is closed.
"""
function _publish!(cam::MagSphereUDP, ch::Channel{MagSphereUDPResult}, result::MagSphereUDPResult)
  lock(cam.latestLock) do
    cam.latest = result
    cam.frameCount += 1
  end
  try
    if Base.n_avail(ch) >= ch.sz_max && isready(ch)
      take!(ch)
      n = lock(() -> (cam.overflowFrames += 1), cam.latestLock)
      n == 1 && @warn "MagSphereUDP: frame channel full ($(ch.sz_max) frames), dropping the oldest. " *
                      "Nobody takes frames fast enough; further drops are only counted in `overflowFrames`."
    end
    put!(ch, result)
  catch e
    e isa InvalidStateException && return false   # channel closed by disable()
    rethrow()
  end
  return true
end

# --- Frame parsing ---------------------------------------------------------

# Read little-/big-endian numbers at 1-based byte position i without allocating.
@inline _u16le(b, i) = UInt16(b[i]) | (UInt16(b[i+1]) << 8)
@inline _u32le(b, i) = UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
@inline _f32le(b, i) = reinterpret(Float32, _u32le(b, i))
@inline function _u64be(b, i)
  v = UInt64(0)
  for k in 0:7
    v = (v << 8) | UInt64(b[i+k])
  end
  return v
end

"""
    _checksumOK(bytes, off)

True if the XOR of the 17 bytes starting at `off` equals the checksum byte
that follows them.
"""
function _checksumOK(b::Vector{UInt8}, off::Int)
  c = 0x00
  for k in 0:16
    c ⊻= b[off+k]
  end
  return c == b[off+17]
end

"""
    parseFrame(cam::MagSphereUDP, bytes, received = time()) -> MagSphereUDPResult or nothing

Turn one UDP datagram into a `MagSphereUDPResult`. Returns `nothing` if the
frame itself is malformed (wrong length or missing 0xAB/0xBA). Inside a good
frame, each sensor packet is checked separately: a bad start marker, checksum
or sensor ID marks only that sensor invalid and sets its values to NaN.
Field values are converted from µT to Tesla.
"""
function parseFrame(cam::MagSphereUDP, b::Vector{UInt8}, received::Float64 = time())
  N = MAGSPHERE_UDP_NUM_SENSORS
  H = MAGSPHERE_UDP_HEADER_SIZE
  (length(b) == MAGSPHERE_UDP_FRAME_SIZE && b[H+1] == 0xAB && b[end] == 0xBA) || return nothing

  timestamp = _u64be(b, 1)
  hubTemperature = Float64(_f32le(b, 9))
  checkIds = cam.params.verifySensorIds

  data = Matrix{typeof(1.0u"T")}(undef, 3, N)
  sensorTemperature = Vector{Float64}(undef, N)
  valid = falses(N)

  for s in 1:N
    off = H + 2 + (s - 1) * MAGSPHERE_UDP_PACKET_SIZE   # sensor 1 starts at byte 14
    ok = b[off] == 0xAA && b[off+1] == 0x55 && _checksumOK(b, off) &&
         (!checkIds || b[off+2] == MAGSPHERE_UDP_LOCAL_ID[s])
    valid[s] = ok
    if ok
      for (axis, k) in enumerate((3, 7, 11))
        data[axis, s] = Float64(_f32le(b, off + k)) * 1e-6 * u"T"   # µT -> T
      end
      sensorTemperature[s] = _u16le(b, off + 15) / 10
    else
      data[:, s] .= NaN * u"T"
      sensorTemperature[s] = NaN
    end
  end
  return MagSphereUDPResult(timestamp, received, hubTemperature, data, sensorTemperature, valid)
end

# --- Single measurements ---------------------------------------------------

"""
    acquireFrame(cam::MagSphereUDP; timeout = cam.params.timeout) -> MagSphereUDPResult or nothing

Return one fresh frame, taken after the call, or `nothing` on timeout.

- Stream running: waits for the next frame the reader task publishes, without
  touching the socket or consuming the channel, so a recording via `take!`
  loses nothing.
- Stream stopped: `_readDirect` takes one frame; with the internal trigger it
  starts and stops the sphere around it, with the external trigger it waits
  for the next BNC edge.
"""
function acquireFrame(cam::MagSphereUDP; timeout = cam.params.timeout)
  t = _strip(u"s", timeout)
  mode, payload = lock(cam.lock) do
    if isrunning(cam)
      (:stream, _frameCount(cam))
    else
      (:direct, _readDirect(cam, t))
    end
  end
  mode === :direct && return payload

  n0 = payload
  status = timedwait(() -> _frameCount(cam) > n0 || !isrunning(cam), t; pollint = 0.005)
  status === :ok || return nothing
  return lock(cam.latestLock) do
    cam.frameCount > n0 ? cam.latest : nothing
  end
end

"""
    getXYZValues(cam::MagSphereUDP; timeout = cam.params.timeout)

The framework's way to read the field camera: a fresh 3×114 matrix in Tesla
(column s = sensor ID s, NaN for invalid sensors), or `nothing` on timeout.
Thin wrapper around `acquireFrame`; use that one if you also need the
timestamp, temperatures or validity mask.
"""
function getXYZValues(cam::MagSphereUDP; kwargs...)
  frame = acquireFrame(cam; kwargs...)
  return isnothing(frame) ? nothing : frame.data
end

"""
    _readDirect(cam, timeout)

Single measurement without a running stream: bind the data port, send `start`
(internal trigger only), wait for the first good frame (`_firstValidFrame`),
send `stop` (internal trigger only) and close the socket, which also unblocks
the receive on timeout. The caller must hold `cam.lock`, so `enable` cannot
start a reader in the meantime.
"""
function _readDirect(cam::MagSphereUDP, timeout::Float64)
  sock = _openDataSocket(cam.params)     # bind before "start" so the first frame is not missed
  reader = @async _firstValidFrame(cam, sock)
  try
    _freeRunning(cam) && sendCommand(cam, "start")
    timedwait(() -> istaskdone(reader), timeout; pollint = 0.005)
  finally
    _freeRunning(cam) && _trySend(cam, "stop")
    close(sock)
  end
  timedwait(() -> istaskdone(reader), 1.0; pollint = 0.005)
  (istaskdone(reader) && !istaskfailed(reader)) || return nothing
  result = fetch(reader)
  _warnInvalidSensors(cam, result)
  return result
end

"""
    _firstValidFrame(cam, sock)

Receive datagrams until one parses as a frame and return it. Runs as a small
task inside `_readDirect`; ends with an error when the socket is closed.
"""
function _firstValidFrame(cam::MagSphereUDP, sock::Sockets.UDPSocket)
  while true
    bytes = Sockets.recv(sock)
    result = parseFrame(cam, bytes, time())
    isnothing(result) || return result
    _countDropped(cam, length(bytes))
  end
end

# --- Diagnostics -----------------------------------------------------------

"""
    _countDropped(cam, len)

Count a malformed frame in `cam.droppedFrames`. Logs a warning only for the
first one since `enable`, so a wrong frame format can't flood the log.
"""
function _countDropped(cam::MagSphereUDP, len::Int)
  n = lock(() -> (cam.droppedFrames += 1), cam.latestLock)
  n == 1 && @warn "MagSphereUDP: dropped a frame of $len bytes (expected $(MAGSPHERE_UDP_FRAME_SIZE) " *
                  "with 0xAB/0xBA markers). Further drops are only counted in `droppedFrames`."
end

"""
    _warnInvalidSensors(cam, result)

Log sensors that sent an invalid packet, each only once per `enable`, with
their board numbers so a failed subsystem can be found with Table 5.
"""
function _warnInvalidSensors(cam::MagSphereUDP, result::MagSphereUDPResult)
  all(result.valid) && return
  newIds = [s for s in eachindex(result.valid) if !result.valid[s] && !cam.warnedSensors[s]]
  isempty(newIds) && return
  cam.warnedSensors[newIds] .= true
  @warn "MagSphereUDP: invalid packets (start marker, checksum or sensor ID) from sensors $newIds " *
        "on boards $(sort(unique(MAGSPHERE_UDP_BOARD[newIds]))); their values are NaN. " *
        "Further failures of these sensors are not logged."
end

# --- Shutdown --------------------------------------------------------------

"""
    close(cam::MagSphereUDP)

Stop the stream (`disable`, which also sends `stop` with the internal trigger)
and close the command socket. The device needs `_init` again afterwards.
"""
function close(cam::MagSphereUDP)
  disable(cam)
  lock(cam.cmdLock) do
    isnothing(cam.cmdSocket) || close(cam.cmdSocket)
    cam.cmdSocket = nothing
  end
end

# --- Geometry and hardware mapping (Table 5 of the manual) -----------------

"Number of sensors on the sphere."
numSensors(::MagSphereUDP) = MAGSPHERE_UDP_NUM_SENSORS

"""
    sensorPositions(cam::MagSphereUDP)

3×114 matrix of sensor positions in metres (column s = sensor ID s), in the
sphere frame of Sect. 2.7 of the manual. All sensors lie on a 90 mm radius.
"""
sensorPositions(::MagSphereUDP) = MAGSPHERE_UDP_POSITIONS_MM .* 1e-3 .* u"m"

# Board ("Platine") of each sensor, for diagnostics
const MAGSPHERE_UDP_BOARD = [
  1, 13, 13, 14, 1, 1, 7, 7, 13, 13, 13, 13, 14, 14, 1, 1, 1, 1, 7,
  7, 11, 11, 11, 13, 14, 14, 14, 14, 1, 3, 3, 2, 2, 2, 7, 7, 11, 11,
  11, 13, 12, 12, 12, 12, 14, 3, 3, 3, 2, 2, 2, 2, 7, 7, 11, 10, 10,
  10, 10, 12, 12, 12, 12, 3, 3, 3, 6, 2, 5, 5, 5, 5, 11, 10, 10, 10,
  10, 9, 9, 9, 9, 6, 6, 6, 6, 5, 5, 5, 5, 8, 8, 8, 8, 9, 9,
  9, 6, 6, 6, 4, 4, 4, 8, 8, 8, 9, 15, 4, 4, 4, 4, 8, 15, 4,
]

# ID byte each packet should carry: (Bus - 1) * 4 + Sensor, checked by parseFrame
const MAGSPHERE_UDP_LOCAL_ID = [
  7, 2, 4, 2, 4, 5, 1, 2, 1, 3, 5, 6, 4, 5, 2, 3, 6, 8, 3,
  4, 4, 7, 8, 7, 1, 3, 6, 7, 1, 6, 8, 3, 5, 8, 5, 6, 3, 5,
  6, 8, 8, 6, 4, 2, 8, 4, 5, 7, 1, 4, 6, 7, 7, 8, 2, 7, 6,
  4, 1, 7, 5, 3, 1, 1, 2, 3, 2, 2, 8, 6, 3, 2, 1, 8, 5, 3,
  2, 8, 5, 3, 1, 7, 6, 4, 1, 7, 5, 4, 1, 7, 5, 4, 2, 7, 4,
  2, 8, 5, 3, 5, 2, 1, 8, 6, 1, 6, 2, 8, 7, 4, 3, 3, 1, 6,
]

# Sensor positions in mm, x y z per row, sensor ID in the comment
const MAGSPHERE_UDP_POSITIONS_MM = permutedims([
                  0.0                 0.0                90.0   #   1
    29.55701500412341                 0.0   85.00813410519032   #   2
   27.998250179459163  29.954294190592744   80.11765252696709   #   3
  -1.4110834930714447  28.666227804533406   85.30097436040327   #   4
   -30.37808557170985  14.635908829173172    83.4443653125451   #   5
   -31.82951066509576 -13.359190150791372   83.11687126772489   #   6
  -1.7414507488421778  -27.84603852323736   85.56614685640425   #   7
   28.553335751480795 -30.034784048551824   79.89129342187461   #   8
    53.63061363900136 -12.533689311438684   71.18050233700579   #   9
    53.65585719417221   20.47992526853651    69.2937345634781   #  10
    43.17438621875907   51.74703091255903   59.65079350996167   #  11
   14.801820439654602   56.51037205447898   68.46520256259076   #  12
  -15.052190775970315   51.18880318222089   72.47853462657511   #  13
  -40.874592060780174   38.56722777047343   70.29819817011834   #  14
  -58.079680863386876   9.645254829124521    68.0714310859437   #  15
   -58.44506314992735  -19.44139909866517   65.62169301753364   #  16
   -33.91852160657525  -40.03168505066344    73.1231706371433   #  17
   -4.436667065532466 -52.676033829037046   72.83921639743087   #  18
   26.424069887458682 -55.026071796101505   66.13546668220451   #  19
    53.44017779526714  -43.02044162626843   58.25280250332225   #  20
    72.30477781214904  -18.98761393407509  50.114764517318406   #  21
    72.45274805911282  13.221877179906366  51.727954362435334   #  22
    64.27211582583648  45.172434384176086   43.91521716987823   #  23
    48.59669167770746   69.97653297941062   29.01114251737247   #  24
   24.126505779567008   74.67590287245923   44.06156203599178   #  25
   -6.638175065294313   74.17990108617539  50.529960485317396   #  26
  -33.384032202223544   68.17795619958228   48.34534809440035   #  27
   -56.31469412634575  50.441897758986364   48.82898909385781   #  28
   -71.50321872570541  23.835857750707632   49.18476997152637   #  29
   -78.23543655245807  -8.693093571158443  43.630798658853244   #  30
   -66.86787749684834 -39.497189073176905  45.482513281306225   #  31
  -44.487305343717914   -57.0486133508477  53.538167488253535   #  32
  -16.432934875974198  -70.31016377024257  53.725594663657816   #  33
   12.409234061690816  -75.13763108346227  47.961936003123334   #  34
   41.649527377970706  -69.04436961821276   39.97739227632648   #  35
    66.60223460646849  -50.66332005424205  33.126580664269696   #  36
    83.30790227539072 -24.719167403543523  23.425545486701953   #  37
    85.68266266067928   5.911900588059583   26.89852645335345   #  38
       79.28402336118    35.9680986120318  22.810951797306046   #  39
    65.48940380058293  61.207335300148884   8.049850638325074   #  40
   35.972583189109045   82.32505945325558   5.343954034286262   #  41
    9.188299842184575   86.83257038680613  21.810086337070484   #  42
    -18.8811455891522   85.55626165297969   20.58223586513656   #  43
      -45.43533905496   75.20320402700168  19.496359742733556   #  44
   -66.86975494369754  56.425990106436174   21.08420058428125   #  45
   -81.39767901661187  30.629683706740572  23.156863490845517   #  46
   -87.65555993312567   0.940943247576861  20.386697589728755   #  47
   -82.10479738429989 -31.900715359529755   18.47015446695892   #  48
   -65.37786071352542  -58.21098068851532   20.90973590947929   #  49
  -41.590694946643886  -74.44313915365237   28.78251425440728   #  50
  -14.880171844993278  -85.01196785374302  25.525395344590308   #  51
    14.17490436617466  -86.57698135473855  20.087269244749425   #  52
    42.92422485773881   -77.9783292370893  13.300040968146735   #  53
     67.5618698353076 -59.070245074007325   6.789690070516205   #  54
    83.96494482218439 -32.350933002350104 -1.8180139947164824   #  55
    89.87755183802933   4.566705735717843 -1.0820694643640774   #  56
    82.78225795993025  34.785401673362124    -6.0888092007067   #  57
   63.334186435160326  61.019525112821654  -19.11539650653584   #  58
    39.67645402420108   77.58020085495585 -22.518690711721376   #  59
    9.249454242550385   88.97482527925732  -9.895860889311242   #  60
  -19.251612225056686   87.31711940829388 -10.251638160498873   #  61
  -46.333705091369815    76.3578863749904 -11.075240893543787   #  62
   -69.08219902712047   56.96893941894535  -9.065854568536297   #  63
   -83.93442663693429   31.77546562659805  -6.732890118068232   #  64
   -89.43511257790394   3.713186746286107  -9.358038382703614   #  65
   -85.63082462203872  -26.63109845039053  -7.625383260876548   #  66
    -69.6015151459293  -56.47488521425006  -8.137347812908992   #  67
  -46.138942444669475  -77.25214978027262 -1.8175104989533248   #  68
  -18.853411316381674  -87.90567746703844   -4.14013898273222   #  69
   10.352279962280138  -88.92519417697758    -9.2271414950354   #  70
    37.96276216146616  -80.16611876904994 -15.238834948201603   #  71
    61.85898873591945  -62.14250212748865  -20.29223846424205   #  72
     76.5241918368714  -37.28858541054438  -29.21659565716444   #  73
    86.57098621324398  -6.656212677085564 -23.688798594773136   #  74
    78.94299251029483  29.290433347304248  -31.78166842452834   #  75
    59.96536688869519   48.96925313080052  -45.89299534477739   #  76
    35.78544736551349   64.96940752557117 -50.974286092365425   #  77
    11.68498259537507   80.10646913414544  -39.32448072900626   #  78
  -17.295675995674163   79.15615479167958 -39.181153000496565   #  79
   -46.69857795046324   66.78772922490866  -38.19217252768934   #  80
   -69.10572110988291   44.53279192915713   -36.6228037276979   #  81
   -79.99915653560689  17.269699877116718  -37.44185385028071   #  82
   -81.26427816298822 -14.415388407977346  -35.89308668386753   #  83
   -70.56589101572442   -45.3127004165308  -32.66824461336474   #  84
   -45.23124023362855  -71.85693362544241  -29.84486550273844   #  85
  -16.270181966207886  -81.81415462359062  -33.78942559461002   #  86
   12.324690325496835  -79.89541342681572  -39.55786801306152   #  87
    38.81560251354965   -67.7043274802489 -44.827146261582726   #  88
   56.033543785339425  -47.75289413402531  -51.76778025604895   #  89
    70.09795238326352  -18.99967176990298 -53.153452797628034   #  90
    74.90776746797924   7.988078055513505  -49.24446143417728   #  91
    54.79859270080914  28.737295459202574  -65.35504638282586   #  92
    28.68457388151872  45.320907094771364  -72.27178288476627   #  93
    3.783369914175125  62.885069737859524  -64.27405476673351   #  94
  -27.327498395425327   60.11727066604513  -61.14835728875711   #  95
   -52.72769409010091   40.81417388964033  -60.44827115515331   #  96
    -65.9515736516306  10.473719676188765  -60.33813992010494   #  97
   -65.57391309685296  -22.96535443291017  -57.20711858673332   #  98
  -49.167946448764695  -54.26716056096451 -52.321967916563544   #  99
  -21.030054340574264  -65.65284832513079 -57.857068031744085   # 100
    9.139177783757372  -62.46793687255093  -64.14228162705056   # 101
   28.743078259397954 -45.674164990947425  -72.02573223892858   # 102
    46.71992495103484 -23.616603841672223  -73.20863771137381   # 103
    49.98951608690169    4.52845811734091  -74.70302101305467   # 104
     20.6632232300779   22.91342777227581   -84.5458812330244   # 105
   -8.138725092977467  41.288393915470685   -79.5551989611104   # 106
   -35.56799509970367  28.105390974005875   -77.7496284414641   # 107
   -46.68455225916271  -0.497134003734342  -76.94352109270693   # 108
  -42.506299640522585  -32.74578647756011  -72.25598908627678   # 109
  -15.592557949724888  -43.97215641992718  -76.96311841632931   # 110
    7.190819272963123 -27.768191900328297  -85.30662129500924   # 111
   21.350430495207554  -5.403610996889173  -87.26373877999733   # 112
   -9.063625521048333  12.156413233449891  -88.71342801240297   # 113
   -20.76191439678133 -11.709601687331705  -86.78610567887443   # 114
])
