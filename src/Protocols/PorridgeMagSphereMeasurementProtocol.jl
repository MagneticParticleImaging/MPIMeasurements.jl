export PorridgeMagSphereMeasurementProtocol, PorridgeMagSphereMeasurementProtocolParams

#=
PorridgeMagSphereMeasurementProtocol: the Porridge field measurement of
PorridgeFieldMeasurementProtocol.jl with the 114-sensor MagSphere (MagSphereUDP
on its external BNC trigger) instead of the Arduino field camera. The coil,
sequence and temperature helpers are shared with PorridgeFieldMeasurementProtocol.jl.

Every rising edge of the sequence's "trigger" channel makes the sphere send one
frame, and frame i belongs to trigger edge i. A lost frame therefore has to be
noticed, or every later frame would be paired with the wrong coil currents.

Missed frames (sphere timestamps instead of the Arduino's reading_id)
  Each frame carries the sphere's timestamp in µs. Two trigger edges are one
  trigger period T apart (taken from the sequence, 10 ms at 100 Hz), so a frame
  k·T after the previous one means k - 1 frames were lost. They are stored as
  NaN placeholders flagged `missing`, which keeps frame i on edge i.
  The reference is the ideal trigger grid, nudged towards every new timestamp
  to follow the drift between sphere and RedPitaya clocks, not the last raw
  timestamp. A single frame may therefore come up to T/2 late or early
  without being miscounted.
    within ±T/2 of the previous frame       skipped (duplicate or extra edge)
    off the grid by > timingTolerance·T      kept, flagged `irregular`
    clock jump (sphere time set in the Web GUI): backwards, or forward by more
      than 10 s while the PC saw far less time pass      -> new reference
    start, and resume after an overheat pause            -> new reference
  Frames lost before the first received frame of a (re)start can't be seen in
  timestamps. Frames missing at the end are filled with placeholders (tail
  fill), as before.

Storage
  Frames go to a binary stream file in the datasetStore (fixed-size records,
  layout in the .toml beside it), flushed after every batch, so a crash loses
  at most the last batch. FileStorageRequestEvent converts it into HDF5.
=#

const MS_FRAME_MISSING = UInt32(1)     # placeholder for a lost frame
const MS_FRAME_TAIL_FILL = UInt32(2)   # placeholder appended after the last received frame
const MS_FRAME_IRREGULAR = UInt32(4)   # received off the trigger grid
const MS_CLOCK_JUMP_S = 10.0           # forward gaps above this are checked against the PC clock
const MS_GRID_GAIN = 0.05              # how fast the trigger grid follows the sphere clock
const MS_SAVE_BLOCK = 10_000           # frames per block when converting the stream to HDF5

Base.@kwdef mutable struct PorridgeMagSphereMeasurementProtocolParams <: ProtocolParams
  sequence::Union{Sequence, Nothing} = nothing
  statusReportInterval::Int64 = 10_000            # frames between status log lines
  timingTolerance::Float64 = 0.25                 # allowed offset from the trigger grid, in trigger periods
  firstFrameTimeout::typeof(1.0u"s") = 5.0u"s"    # abort if no frame arrives this long after the trigger starts (0 = never)
end

function PorridgeMagSphereMeasurementProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    delete!(dict, "sequence")
  end
  params = params_from_dict(PorridgeMagSphereMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end

PorridgeMagSphereMeasurementProtocolParams(dict::Dict) =
  params_from_dict(PorridgeMagSphereMeasurementProtocolParams, dict)

"Sizes that fix the record layout of the binary frame stream, see writeMagSphereRecord!."
struct MagSphereStreamLayout
  coilNames::Vector{String}
  numCoilTemperatures::Int
  numSensors::Int
end

# frameIndex, patchIndex, timestamp, received (8 bytes each), hub temperature and
# flags (4 each), coil currents (Float64), coil temperatures, field (3 per sensor)
# and sensor temperatures (Float32)
magSphereRecordSize(l::MagSphereStreamLayout) =
  4 * 8 + 2 * 4 + 8 * length(l.coilNames) + 4 * l.numCoilTemperatures + 4 * 4 * l.numSensors

Base.@kwdef mutable struct PorridgeMagSphereMeasurementProtocol <: Protocol
  @add_protocol_fields PorridgeMagSphereMeasurementProtocolParams

  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  unit::String = "frames"

  currentFrameNum::Int64 = 0
  totalFrames::Int64 = 0

  # Missed-frame detection, see the header
  triggerPeriod_us::Float64 = NaN
  gridTime_us::Float64 = NaN        # trigger-grid time of the last stored frame, NaN = no reference
  lastTimestamp::UInt64 = 0
  lastReceived::Float64 = NaN
  periodSum_us::Float64 = 0.0       # single-period steps, for the measured trigger period
  periodCount::Int64 = 0
  maxGridOffset_us::Float64 = 0.0
  receivedFrames::Int64 = 0         # real frames stored
  missingFrames::Int64 = 0          # placeholders for gaps inside the run
  tailFillFrames::Int64 = 0         # placeholders after the last received frame
  skippedFrames::Int64 = 0          # duplicates, extra edges, frames beyond the sequence
  irregularFrames::Int64 = 0
  clockJumps::Int64 = 0

  overheatOccurred::Bool = false
  overheatFrame::Int64 = -1
  overheatCoilID::Int64 = -1
  overheatFrames::Vector{Int64} = Int64[]
  overheatCoilIDs::Vector{Int64} = Int64[]
  overheatTemps::Vector{Float64} = Float64[]

  # Binary frame stream and the buffers one record is assembled in
  streamPath::Union{String,Nothing} = nothing
  streamHandle::Union{IOStream,Nothing} = nothing
  streamLayout::Union{MagSphereStreamLayout,Nothing} = nothing
  coilChannels::Vector{StepwiseElectricalChannel} = StepwiseElectricalChannel[]
  coilTemperatureBuffer::Vector{Float32} = Float32[]
  fieldBuffer::Vector{Float32} = Float32[]
  sensorTemperatureBuffer::Vector{Float32} = Float32[]

  # Anchors for the GC/heap figures in the status log
  runStartTimeNs::UInt64 = UInt64(0)
  runStartGcTimeNs::UInt64 = UInt64(0)
end

requiredDevices(::PorridgeMagSphereMeasurementProtocol) = [AbstractDAQ, MagSphereUDP, TemperatureSensor]

function _init(protocol::PorridgeMagSphereMeasurementProtocol)
  isnothing(protocol.params.sequence) &&
    throw(IllegalStateException("Protocol requires a sequence"))
  cam = getDevice(protocol.scanner, MagSphereUDP)
  cam.triggerMode == "external" ||
    throw(IllegalStateException("PorridgeMagSphereMeasurementProtocol needs the MagSphere on the external " *
      "(BNC) trigger, so that frame i belongs to trigger edge i. Set triggerMode = \"external\" for device " *
      "`$(deviceID(cam))` (currently \"$(cam.triggerMode)\")."))
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentFrameNum = 0
  closeMagSphereStream!(protocol)
end

function enterExecute(protocol::PorridgeMagSphereMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentFrameNum = 0
  protocol.gridTime_us = NaN
  protocol.lastTimestamp = 0
  protocol.lastReceived = NaN
  protocol.periodSum_us = 0.0
  protocol.periodCount = 0
  protocol.maxGridOffset_us = 0.0
  protocol.receivedFrames = 0
  protocol.missingFrames = 0
  protocol.tailFillFrames = 0
  protocol.skippedFrames = 0
  protocol.irregularFrames = 0
  protocol.clockJumps = 0
  protocol.overheatOccurred = false
  protocol.overheatFrame = -1
  protocol.overheatCoilID = -1
  empty!(protocol.overheatFrames)
  empty!(protocol.overheatCoilIDs)
  empty!(protocol.overheatTemps)
  protocol.runStartTimeNs = time_ns()
  protocol.runStartGcTimeNs = Base.gc_time_ns()
  closeMagSphereStream!(protocol)
  if !isnothing(protocol.params.sequence)
    seq = protocol.params.sequence
    protocol.totalFrames = length(computeTriggerPatches(seq)) * acqNumFrames(seq) * acqNumFrameAverages(seq)
  end
end

function _execute(protocol::PorridgeMagSphereMeasurementProtocol)
  try
    performMagSphereMeasurement(protocol)
    put!(protocol.biChannel, FinishedNotificationEvent())
    while !protocol.finishAcknowledged
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
    end
  catch e
    isa(e, CancelException) && rethrow(e)
    @error "Protocol execution error" exception = e
    rethrow(e)
  end
end

cleanup(protocol::PorridgeMagSphereMeasurementProtocol) = closeMagSphereStream!(protocol)
stop(protocol::PorridgeMagSphereMeasurementProtocol) = (protocol.stopped = true)
cancel(protocol::PorridgeMagSphereMeasurementProtocol) = (protocol.cancelled = true)

function resume(protocol::PorridgeMagSphereMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function timeEstimate(protocol::PorridgeMagSphereMeasurementProtocol)
  seq = protocol.params.sequence
  isnothing(seq) && return "Unknown"
  patches = computeTriggerPatches(seq)
  frames = length(patches) * acqNumFrames(seq) * acqNumFrameAverages(seq)
  return string(round(frames * magSphereTriggerPeriod(seq, patches) / 60, digits = 1) * 1u"minute")
end

function recordOverheat!(protocol::PorridgeMagSphereMeasurementProtocol, frame::Int64, coilID::Int64, temp::Float64)
  protocol.overheatOccurred = true
  protocol.overheatFrame = frame
  protocol.overheatCoilID = coilID
  push!(protocol.overheatFrames, frame)
  push!(protocol.overheatCoilIDs, coilID)
  push!(protocol.overheatTemps, temp)
end

"""
    magSphereTriggerPeriod(sequence, triggerPatches) -> Float64

Time between two rising edges of the sequence's "trigger" channel, in seconds.
The missed-frame detection needs it to be the same for every pair of edges.
"""
function magSphereTriggerPeriod(sequence::Sequence, triggerPatches::Vector{Int})
  length(triggerPatches) >= 2 ||
    throw(IllegalStateException("The sequence needs at least two trigger edges."))
  spacing = triggerPatches[2] - triggerPatches[1]
  all(i -> triggerPatches[i+1] - triggerPatches[i] == spacing, 1:length(triggerPatches)-1) ||
    throw(IllegalStateException("The trigger edges are not evenly spaced; missed-frame detection " *
                                "from timestamps needs a constant trigger period."))
  for field in fields(sequence), channel in channels(field)
    if id(channel) == "trigger" && isa(channel, StepwiseElectricalChannel)
      stepTime = channel.divider / (length(channel.values) * ustrip(u"Hz", txBaseFrequency(sequence)))
      return spacing * stepTime
    end
  end
  throw(IllegalStateException("The sequence has no stepwise \"trigger\" channel."))
end

function performMagSphereMeasurement(protocol::PorridgeMagSphereMeasurementProtocol)
  protocol.measuring = true

  scanner_ = protocol.scanner
  daq = getDAQ(scanner_)
  cam = getDevice(scanner_, MagSphereUDP)
  tempSensor = getTemperatureSensor(scanner_)
  sequence = protocol.params.sequence

  triggerPatches = computeTriggerPatches(sequence)
  repetitions = acqNumFrames(sequence) * acqNumFrameAverages(sequence)
  protocol.totalFrames = length(triggerPatches) * repetitions
  period_s = magSphereTriggerPeriod(sequence, triggerPatches)
  protocol.triggerPeriod_us = period_s * 1e6

  @info "Starting MagSphere field measurement" triggers=length(triggerPatches) total=protocol.totalFrames trigger_rate_Hz=round(1 / period_s, digits=3) duration_h=round(protocol.totalFrames * period_s / 3600, digits=2)
  if repetitions != 1
    @warn "Overheat resume assumes a single sequence repetition" repetitions
  end

  coilTemperatures, _, _, _, _ = readCoilTemperatures(tempSensor)
  openMagSphereStream!(protocol, sequence, length(coilTemperatures), numSensors(cam))

  tempCheckInterval = 0.2
  firstFrameTimeout = ustrip(u"s", protocol.params.firstFrameTimeout)
  silenceWarning = max(2.0, 20 * period_s)
  outcome = :complete

  enable(cam)
  try
    while true
      # On resume (after an overheat cooldown) start on the LOW step of the frame captured
      # last, so the next frame's trigger is a real rising edge; see performFieldMeasurement.
      runSequence = protocol.currentFrameNum == 0 ? sequence :
                    sliceSequenceFromStep(sequence, 2 * protocol.currentFrameNum)
      setup(daq, runSequence)
      discardUntriggeredFrames!(cam)
      protocol.gridTime_us = NaN   # the first frame after (re)starting begins a new trigger grid
      startTx(daq)
      finish = getTiming(daq).finish
      startedAt = time()
      receivedAtStart = protocol.receivedFrames
      lastArrival = startedAt

      overheated = false
      nextTempCheck = time()
      while currentWP(daq.rpc) < finish
        if time() >= nextTempCheck
          nextTempCheck = time() + tempCheckInterval
          coilTemperatures, overheat, overheatCoil, overheatTemp, overheatMax = readCoilTemperatures(tempSensor)
          if overheat
            recordOverheat!(protocol, protocol.currentFrameNum, overheatCoil, overheatTemp)
            @warn "Overheat detected, ramping down to cool" coil_label=coilChannelLabel(overheatCoil) temperature=round(overheatTemp, digits=1) max=overheatMax frame=protocol.currentFrameNum
            rampDownAndWait!(daq, protocol)
            finish = currentWP(daq.rpc)
            overheated = true
            break
          end
        end

        if storeMagSphereFrames!(protocol, cam, triggerPatches, coilTemperatures) > 0
          lastArrival = time()
        elseif protocol.receivedFrames == receivedAtStart && firstFrameTimeout > 0 &&
               time() - startedAt > firstFrameTimeout
          @error "No MagSphere frame within $(firstFrameTimeout) s after the trigger started; aborting. Check the " *
                 "BNC cable, the trigger level (the white LED in the sphere shows the edges) and that the sphere is in BNC trigger mode."
          rampDownAndWait!(daq, protocol)
          finish = currentWP(daq.rpc)
          outcome = :noFrames
          break
        elseif time() - lastArrival > silenceWarning
          @warn "No MagSphere frame for $(round(time() - lastArrival, digits=1)) s while the trigger runs" frame=protocol.currentFrameNum maxlog=10
          lastArrival = time()
        end

        handleEvents(protocol)
        if protocol.cancelled || protocol.stopped
          rampDownAndWait!(daq, protocol)
          finish = currentWP(daq.rpc)
          outcome = :stopped
          break
        end
      end

      endSequence(daq, finish)
      drainMagSphereFrames!(protocol, cam, triggerPatches, coilTemperatures)

      if outcome != :complete || protocol.currentFrameNum >= protocol.totalFrames
        break
      elseif overheated
        coil = coilChannelLabel(protocol.overheatCoilID)
        @info "Waiting for $coil to cool down before resuming" frame=protocol.currentFrameNum
        if !waitForCoilCooling(tempSensor, protocol.overheatCoilID)
          outcome = :cooldownTimeout
          break
        end
        @info "Resuming measurement" frame=protocol.currentFrameNum
      else
        break
      end
    end

    if outcome == :complete && protocol.currentFrameNum < protocol.totalFrames
      appendMagSphereTailFill!(protocol, triggerPatches, coilTemperatures)
    end
  finally
    disable(cam)
    isnothing(protocol.streamHandle) || flush(protocol.streamHandle)
    protocol.measuring = false
  end

  logMagSphereSummary(protocol, cam)

  outcome == :noFrames && error("The MagSphere sent no frames after the trigger started; see the log above.")
  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
  end
  protocol.cancelled && throw(CancelException())

  @info "Field measurement complete" frames=protocol.currentFrameNum target=protocol.totalFrames
end

"""
    discardUntriggeredFrames!(cam)

Called after the sequence is set up and just before the trigger starts. Frames
already here were not caused by the sequence. A few mean the trigger line
twitched; they are dropped, otherwise every later frame would be shifted by
one. Many mean the sphere still runs on its internal clock, which makes the
frames useless for this protocol, so that is an error.
"""
function discardUntriggeredFrames!(cam::MagSphereUDP)
  sleep(0.3)   # a free-running sphere sends dozens of frames in this time
  n = 0
  while isready(cam.ch)
    take!(cam.ch)
    n += 1
  end
  n > 3 && throw(IllegalStateException("The MagSphere sent $n frames before the trigger started, so it is still " *
    "running on its internal clock. Check that `oneshot_on` and `trigger` reach it (Web GUI: One-Shot, BNC Trigger)."))
  n > 0 && @warn "Discarded $n MagSphere frame(s) that arrived before the trigger started (a twitch on the trigger line?)."
  return n
end

"""
    storeMagSphereFrames!(protocol, cam, triggerPatches, coilTemperatures) -> Int

Take every frame waiting in the sphere's channel, add placeholders for frames
the timestamps show as lost, append all of them to the stream and return the
number of frames taken from the channel.
"""
function storeMagSphereFrames!(protocol::PorridgeMagSphereMeasurementProtocol, cam::MagSphereUDP,
                               triggerPatches::Vector{Int}, coilTemperatures::Vector{Float64})
  taken = 0
  while isready(cam.ch)
    frame = take!(cam.ch)
    taken += 1
    if protocol.currentFrameNum >= protocol.totalFrames
      protocol.skippedFrames += 1
      @warn "The MagSphere sent more frames than the sequence has trigger edges; extra frames are skipped" maxlog=1
      continue
    end

    previousTimestamp = protocol.lastTimestamp
    k, irregular = magSphereFramesSinceLast!(protocol, frame)
    k == 0 && continue
    if k > 1
      @warn "Missed MagSphere frames detected from the timestamps" missing=(k - 1) first_missing_frame=(protocol.currentFrameNum + 1) gap_ms=round((Float64(frame.timestamp) - Float64(previousTimestamp)) / 1000, digits=2) maxlog=100
      for _ in 1:(k - 1)
        protocol.currentFrameNum >= protocol.totalFrames && break
        writeMagSphereRecord!(protocol, nothing, triggerPatches, coilTemperatures, MS_FRAME_MISSING)
        protocol.missingFrames += 1
      end
      if protocol.currentFrameNum >= protocol.totalFrames
        protocol.skippedFrames += 1
        continue
      end
    end

    writeMagSphereRecord!(protocol, frame, triggerPatches, coilTemperatures,
                          irregular ? MS_FRAME_IRREGULAR : UInt32(0))
    protocol.receivedFrames += 1
    reportMagSphereStatus(protocol, cam)
  end
  taken > 0 && flush(protocol.streamHandle)
  return taken
end

"""
    magSphereFramesSinceLast!(protocol, frame) -> (k, irregular)

Trigger periods between `frame` and the last stored frame: 1 for the next frame,
k > 1 when k - 1 frames were lost, 0 when `frame` is to be skipped. `irregular`
is true when the frame is more than `timingTolerance` periods off the trigger
grid. Moves the grid on to this frame. The rules are in the file header.
"""
function magSphereFramesSinceLast!(protocol::PorridgeMagSphereMeasurementProtocol, frame::MagSphereUDPResult)
  if isnan(protocol.gridTime_us)
    newMagSphereReference!(protocol, frame)
    return 1, false
  end
  if frame.timestamp == protocol.lastTimestamp
    protocol.skippedFrames += 1
    @warn "The MagSphere sent a frame twice (same timestamp); skipped" timestamp=frame.timestamp maxlog=10
    return 0, false
  end

  T = protocol.triggerPeriod_us
  dt = Float64(frame.timestamp) - protocol.gridTime_us
  if dt < -T / 2 ||
     (dt > MS_CLOCK_JUMP_S * 1e6 && frame.received - protocol.lastReceived < dt * 1e-6 / 2)
    protocol.clockJumps += 1
    @warn "The MagSphere clock jumped (system time set during the measurement?); timing reference restarted, " *
          "frames lost right at the jump can't be detected" jump_s=round(dt * 1e-6, digits=3) frame=(protocol.currentFrameNum + 1) maxlog=10
    newMagSphereReference!(protocol, frame)
    return 1, false
  end

  k = round(Int, dt / T)
  if k == 0
    protocol.skippedFrames += 1
    @warn "MagSphere frame only $(round(dt / 1000, digits=2)) ms after the previous one (trigger period " *
          "$(round(T / 1000, digits=3)) ms); skipped as an extra trigger edge. Many of these mean the sphere " *
          "triggers on both edges or the trigger line is noisy." frame=protocol.currentFrameNum maxlog=10
    return 0, false
  end

  offset = dt - k * T
  irregular = abs(offset) > protocol.params.timingTolerance * T
  if irregular
    protocol.irregularFrames += 1
    @warn "MagSphere frame $(round(offset / 1000, digits=2)) ms off the trigger grid; kept and flagged irregular, " *
          "the missed-frame count may be wrong around it" frame=(protocol.currentFrameNum + k) maxlog=20
  end
  protocol.maxGridOffset_us = max(protocol.maxGridOffset_us, abs(offset))
  if k == 1
    protocol.periodSum_us += Float64(frame.timestamp) - Float64(protocol.lastTimestamp)
    protocol.periodCount += 1
  end
  protocol.gridTime_us += k * T + MS_GRID_GAIN * offset
  protocol.lastTimestamp = frame.timestamp
  protocol.lastReceived = frame.received
  return k, irregular
end

function newMagSphereReference!(protocol::PorridgeMagSphereMeasurementProtocol, frame::MagSphereUDPResult)
  protocol.gridTime_us = Float64(frame.timestamp)
  protocol.lastTimestamp = frame.timestamp
  protocol.lastReceived = frame.received
end

"""
    drainMagSphereFrames!(protocol, cam, triggerPatches, coilTemperatures)

After the sequence ended: store the frames still on their way until none has
arrived for a while (at least 0.5 s) or all frames are there.
"""
function drainMagSphereFrames!(protocol::PorridgeMagSphereMeasurementProtocol, cam::MagSphereUDP,
                               triggerPatches::Vector{Int}, coilTemperatures::Vector{Float64})
  quiet = max(0.5, 50 * protocol.triggerPeriod_us * 1e-6)
  lastArrival = time()
  while protocol.currentFrameNum < protocol.totalFrames && time() - lastArrival < quiet
    if storeMagSphereFrames!(protocol, cam, triggerPatches, coilTemperatures) > 0
      lastArrival = time()
    else
      sleep(0.01)
    end
  end
end

function appendMagSphereTailFill!(protocol::PorridgeMagSphereMeasurementProtocol, triggerPatches::Vector{Int},
                                  coilTemperatures::Vector{Float64})
  n = protocol.totalFrames - protocol.currentFrameNum
  n <= 0 && return 0
  for _ in 1:n
    writeMagSphereRecord!(protocol, nothing, triggerPatches, coilTemperatures, MS_FRAME_MISSING | MS_FRAME_TAIL_FILL)
  end
  protocol.tailFillFrames += n
  flush(protocol.streamHandle)
  @warn "Tail frames missing from the MagSphere stream; filled with NaN placeholders" missing=n
  return n
end

function reportMagSphereStatus(protocol::PorridgeMagSphereMeasurementProtocol, cam::MagSphereUDP)
  every = protocol.params.statusReportInterval
  (every > 0 && protocol.currentFrameNum % every == 0) || return
  elapsedNs = time_ns() - protocol.runStartTimeNs
  gcElapsedNs = Base.gc_time_ns() - protocol.runStartGcTimeNs
  gcPercent = elapsedNs > 0 ? round(gcElapsedNs / elapsedNs * 100, digits=2) : 0.0
  @info "Measurement $(protocol.currentFrameNum)/$(protocol.totalFrames)" missing=protocol.missingFrames skipped=protocol.skippedFrames irregular=protocol.irregularFrames max_grid_offset_ms=round(protocol.maxGridOffset_us / 1000, digits=3) backlog=Base.n_avail(cam.ch) channel_overflows=cam.overflowFrames gc_time_pct=gcPercent live_heap_mb=round(Base.gc_live_bytes() / 2^20, digits=1) rss_mb=round(Sys.maxrss() / 2^20, digits=1)
end

function measuredMagSpherePeriod_s(protocol::PorridgeMagSphereMeasurementProtocol)
  return protocol.periodCount > 0 ? protocol.periodSum_us / protocol.periodCount * 1e-6 : NaN
end

function logMagSphereSummary(protocol::PorridgeMagSphereMeasurementProtocol, cam::MagSphereUDP)
  @info "MagSphere frame summary" frames=protocol.currentFrameNum target=protocol.totalFrames received=protocol.receivedFrames missing=protocol.missingFrames tail_fill=protocol.tailFillFrames skipped=protocol.skippedFrames irregular=protocol.irregularFrames clock_jumps=protocol.clockJumps trigger_period_ms=round(protocol.triggerPeriod_us / 1000, digits=4) measured_period_ms=round(measuredMagSpherePeriod_s(protocol) * 1000, digits=4) max_grid_offset_ms=round(protocol.maxGridOffset_us / 1000, digits=3) malformed_datagrams=cam.droppedFrames channel_overflows=cam.overflowFrames
  lost = protocol.missingFrames + protocol.tailFillFrames
  lost > 0 && @warn "$lost of $(protocol.totalFrames) frames are NaN placeholders for missed MagSphere frames (flagged in /frames/missing)"
end

# --- Binary frame stream ---------------------------------------------------

"""
    openMagSphereStream!(protocol, sequence, numCoilTemperatures, numSensors)

Create the stream file `measurement_<time>_magsphere_stream.bin` in the
datasetStore and a `.toml` beside it that describes the record layout, so the
data stay readable even if the run dies before the HDF5 file is written.
"""
function openMagSphereStream!(protocol::PorridgeMagSphereMeasurementProtocol, sequence::Sequence,
                              numCoilTemperatures::Int, numSensors::Int)
  closeMagSphereStream!(protocol)
  coilChannels = StepwiseElectricalChannel[ch for field in fields(sequence) for ch in channels(field)
                                           if isa(ch, StepwiseElectricalChannel) && startswith(id(ch), "coil")]
  protocol.coilChannels = sort!(coilChannels; by = ch -> coilChannelSortKey(id(ch)))
  layout = MagSphereStreamLayout([id(ch) for ch in protocol.coilChannels], numCoilTemperatures, numSensors)
  protocol.streamLayout = layout
  protocol.coilTemperatureBuffer = fill(NaN32, numCoilTemperatures)
  protocol.fieldBuffer = fill(NaN32, 3 * numSensors)
  protocol.sensorTemperatureBuffer = fill(NaN32, numSensors)

  store = expanduser(protocol.scanner.generalParams.datasetStore)
  mkpath(store)
  base = joinpath(store, "measurement_$(Dates.format(now(), "yyyymmdd_HHMMSS"))_magsphere_stream")
  protocol.streamPath = base * ".bin"
  protocol.streamHandle = open(protocol.streamPath, "w")
  open(base * ".toml", "w") do io
    TOML.print(io, Dict(
      "description" => "MagSphere frames of PorridgeMagSphereMeasurementProtocol: one fixed-size " *
                       "little-endian record per frame, fields in the order of `record`",
      "recordSize" => magSphereRecordSize(layout),
      "record" => [
        "frameIndex Int64",
        "patchIndex Int64",
        "timestamp_us UInt64 (sphere clock, 0 for placeholders)",
        "received_s Float64 (PC time, NaN for placeholders)",
        "hubTemperature_C Float32",
        "flags UInt32 (1 missing, 2 tail fill, 4 irregular timing)",
        "coilCurrents Float64 x $(length(layout.coilNames)) (order of coilNames)",
        "coilTemperatures_C Float32 x $numCoilTemperatures",
        "field_T Float32 x $(3 * numSensors) (3 x $numSensors, column-major, NaN for invalid sensors)",
        "sensorTemperatures_C Float32 x $numSensors",
      ],
      "coilNames" => layout.coilNames,
      "numSensors" => numSensors,
      "numCoilTemperatures" => numCoilTemperatures,
      "triggerPeriod_s" => protocol.triggerPeriod_us * 1e-6,
      "sequence" => sequence.general.name,
    ))
  end
  @info "Streaming MagSphere frames to $(protocol.streamPath)"
  return protocol.streamPath
end

function closeMagSphereStream!(protocol::PorridgeMagSphereMeasurementProtocol)
  if !isnothing(protocol.streamHandle)
    close(protocol.streamHandle)
    protocol.streamHandle = nothing
  end
end

"""
    writeMagSphereRecord!(protocol, frame, triggerPatches, coilTemperatures, flags)

Append the next frame to the stream as one record (layout in
openMagSphereStream!). `frame = nothing` writes a NaN placeholder.
"""
function writeMagSphereRecord!(protocol::PorridgeMagSphereMeasurementProtocol,
                               frame::Union{MagSphereUDPResult,Nothing}, triggerPatches::Vector{Int},
                               coilTemperatures::Vector{Float64}, flags::UInt32)
  io = protocol.streamHandle
  frameIndex = protocol.currentFrameNum + 1
  patchIdx = triggerPatches[mod1(frameIndex, length(triggerPatches))]

  write(io, Int64(frameIndex), Int64(patchIdx))
  if isnothing(frame)
    write(io, UInt64(0), NaN, NaN32)
    fill!(protocol.fieldBuffer, NaN32)
    fill!(protocol.sensorTemperatureBuffer, NaN32)
  else
    write(io, frame.timestamp, frame.received, Float32(frame.hubTemperature))
    for i in eachindex(protocol.fieldBuffer)
      protocol.fieldBuffer[i] = ustrip(u"T", frame.data[i])
    end
    protocol.sensorTemperatureBuffer .= frame.sensorTemperature
  end
  write(io, flags)
  for ch in protocol.coilChannels
    write(io, Float64(ustrip(ch.values[mod1(patchIdx, length(ch.values))])))
  end
  temps = protocol.coilTemperatureBuffer
  for i in eachindex(temps)
    temps[i] = i <= length(coilTemperatures) ? coilTemperatures[i] : NaN32
  end
  write(io, temps, protocol.fieldBuffer, protocol.sensorTemperatureBuffer)
  protocol.currentFrameNum = frameIndex
end

# --- Events and HDF5 -------------------------------------------------------

function handleEvent(protocol::PorridgeMagSphereMeasurementProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel,
    ProgressEvent(protocol.currentFrameNum, protocol.totalFrames, protocol.unit, event))
end

function handleEvent(protocol::PorridgeMagSphereMeasurementProtocol, event::FinishedAckEvent)
  protocol.finishAcknowledged = true
end

function handleEvent(protocol::PorridgeMagSphereMeasurementProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  @info "Saving measurement data to $filename"
  try
    closeMagSphereStream!(protocol)
    h5open(filename, "w") do file
      saveMagSphereData(file, protocol)
      write(file, "/protocol", string(typeof(protocol)))
      write(file, "/timestamp", string(now()))
      if !isnothing(protocol.params.sequence)
        write(file, "/sequenceName", protocol.params.sequence.general.name)
      end
    end
    put!(protocol.biChannel, StorageSuccessEvent(filename))
    @info "Data saved to $filename"
  catch e
    @error "Save error" exception=e
    put!(protocol.biChannel, ExceptionEvent(e))
  end
end

"""
    saveMagSphereData(file, protocol)

Convert the binary frame stream into HDF5, block by block so the whole run
never has to fit in memory. N frames, S = 114 sensors, all in sphere
coordinates (Sect. 2.7 of the manual):

    /fields                        3 × S × N Float32, T, NaN for missing frames and invalid sensors
    /positions/sensors             3 × S, m
    /sensor/temperature            S × N, °C;  /sensor/hub_temperature  N, °C
    /currents/coil/{channel_names,value}, /temperature/coil/value   as in PorridgeFieldMeasurementProtocol
    /frames/{index,patch_index,missing,tail_fill,irregular_timing}  per frame
    /timing/{sphere_timestamp_us,received_s}                        per frame
    /timing/{trigger_period_s,measured_period_s}, /measurement/...  run summary
"""
function saveMagSphereData(file, protocol::PorridgeMagSphereMeasurementProtocol)
  path = protocol.streamPath
  layout = protocol.streamLayout
  if isnothing(path) || isnothing(layout) || !isfile(path)
    @warn "No MagSphere stream file available; nothing to save"
    return
  end
  n = filesize(path) ÷ magSphereRecordSize(layout)
  if n == 0
    @warn "The MagSphere stream file is empty; nothing to save"
    return
  end
  nS, nC, nT = layout.numSensors, length(layout.coilNames), layout.numCoilTemperatures

  frameIndex = Vector{Int64}(undef, n)
  patchIndex = Vector{Int64}(undef, n)
  timestamps = Vector{UInt64}(undef, n)
  received = Vector{Float64}(undef, n)
  hubTemperature = Vector{Float32}(undef, n)
  flags = Vector{UInt32}(undef, n)
  currents = Matrix{Float64}(undef, nC, n)
  coilTemperatures = Matrix{Float32}(undef, nT, n)
  currentBuffer = Vector{Float64}(undef, nC)
  coilTemperatureBuffer = Vector{Float32}(undef, nT)

  chunkFrames = min(n, 1024)
  fieldsData = create_dataset(file, "/fields", datatype(Float32), dataspace(3, nS, n); chunk=(3, nS, chunkFrames))
  sensorTemperatures = create_dataset(file, "/sensor/temperature", datatype(Float32), dataspace(nS, n); chunk=(nS, chunkFrames))

  @info "Converting MagSphere frames for HDF5" frames=n
  open(path, "r") do io
    for first in 1:MS_SAVE_BLOCK:n
      m = min(MS_SAVE_BLOCK, n - first + 1)
      fieldBlock = Array{Float32}(undef, 3, nS, m)
      temperatureBlock = Matrix{Float32}(undef, nS, m)
      for j in 1:m
        i = first + j - 1
        # Base.read: MPIMeasurements has a `read` of its own for storage buffers
        frameIndex[i] = Base.read(io, Int64)
        patchIndex[i] = Base.read(io, Int64)
        timestamps[i] = Base.read(io, UInt64)
        received[i] = Base.read(io, Float64)
        hubTemperature[i] = Base.read(io, Float32)
        flags[i] = Base.read(io, UInt32)
        currents[:, i] = Base.read!(io, currentBuffer)
        coilTemperatures[:, i] = Base.read!(io, coilTemperatureBuffer)
        Base.read!(io, view(fieldBlock, :, :, j))
        Base.read!(io, view(temperatureBlock, :, j))
      end
      fieldsData[:, :, first:first+m-1] = fieldBlock
      sensorTemperatures[:, first:first+m-1] = temperatureBlock
    end
  end

  cam = getDevice(protocol.scanner, MagSphereUDP)
  positions = ustrip.(u"m", sensorPositions(cam))
  write(file, "/positions/sensors", positions)
  write(file, "/positions/radius", mean(norm.(eachcol(positions))))
  write(file, "/positions/center", [0.0, 0.0, 0.0])
  write(file, "/positions/frame", "MagSphere sphere coordinates (manual Sect. 2.7)")
  write(file, "/sensor/hub_temperature", hubTemperature)
  write(file, "/sensor/measurement_range_mT", ustrip(u"mT", cam.measurementRange))
  write(file, "/sensor/trigger_mode", cam.triggerMode)
  write(file, "/currents/coil/channel_names", labeledCoilChannelName.(layout.coilNames))
  write(file, "/currents/coil/value", currents)
  write(file, "/temperature/coil/value", Float64.(coilTemperatures))
  write(file, "/temperature/unit", "°C")

  write(file, "/frames/index", frameIndex)
  write(file, "/frames/patch_index", patchIndex)
  write(file, "/frames/missing", UInt8.((flags .& MS_FRAME_MISSING) .!= 0))
  write(file, "/frames/tail_fill", UInt8.((flags .& MS_FRAME_TAIL_FILL) .!= 0))
  write(file, "/frames/irregular_timing", UInt8.((flags .& MS_FRAME_IRREGULAR) .!= 0))
  write(file, "/timing/sphere_timestamp_us", timestamps)
  write(file, "/timing/received_s", received)
  write(file, "/timing/trigger_period_s", protocol.triggerPeriod_us * 1e-6)
  write(file, "/timing/measured_period_s", measuredMagSpherePeriod_s(protocol))

  write(file, "/measurement/received_frames", protocol.receivedFrames)
  write(file, "/measurement/missing_frames", protocol.missingFrames)
  write(file, "/measurement/tail_fill_frames", protocol.tailFillFrames)
  write(file, "/measurement/skipped_frames", protocol.skippedFrames)
  write(file, "/measurement/irregular_frames", protocol.irregularFrames)
  write(file, "/measurement/clock_jumps", protocol.clockJumps)
  write(file, "/measurement/overheat_occurred", protocol.overheatOccurred)
  if protocol.overheatOccurred
    write(file, "/measurement/overheat_frame", protocol.overheatFrame)
    write(file, "/measurement/overheat_coil_id", protocol.overheatCoilID)
    write(file, "/measurement/overheat_coil_label", coilChannelLabel(protocol.overheatCoilID))
    write(file, "/measurement/overheat_frames", protocol.overheatFrames)
    write(file, "/measurement/overheat_coil_ids", protocol.overheatCoilIDs)
    write(file, "/measurement/overheat_temps", protocol.overheatTemps)
    write(file, "/measurement/overheat_coil_labels", coilChannelLabel.(protocol.overheatCoilIDs))
  end
end
