#=
LiveFieldFeed: the measurement-process half of the live field view. Sends one settled MagSphere
frame per coil configuration to LiveFieldViewer.jl, which runs as a separate Julia process and
draws it.

  feed = LiveFieldFeed.start(protocol; framesPerConfiguration = 100, status = i -> "...")
  ...
  LiveFieldFeed.stop!(feed)

Settled frames
  Every coil configuration is held for `framesPerConfiguration` trigger edges; configuration k
  covers frames (k-1)·N+1 .. k·N. Right after a step the coils are still ramping, so only the end
  of a configuration shows the field the currents are meant to make. The feed hooks into the
  protocol (protocol.frameObserver, called with the trigger index of every stored frame) and
  keeps the last received frame of each configuration that lies in its final `settledFrames`
  frames: normally frame k·N itself, an earlier one if that frame was lost, none if all of them
  were. That frame is sent as soon as the configuration is over, so the viewer updates once per
  configuration (1 s at 100 Hz, 100 frames). Backgrounds are cut into the same blocks.

  The observer runs on the protocol's thread and only stores a reference to the frame; the
  conversion and the sending happen on the feed's own task.

Sending
  One UDP datagram per new settled frame to 127.0.0.1:port (layout in LiveFieldPacket.jl), and
  the last one again every `heartbeat_s` while no new one comes (between uploads, after an
  overheat), so the viewer can tell "measurement paused" from "measurement gone". Nobody waits
  for a receiver: without a viewer the datagrams are dropped, so the viewer can be opened,
  closed or restarted at any time during a run.

The feed's task is pinned to a worker thread (2 by default), never to thread 1, so Ctrl+C still
reaches the measurement script's main loop exactly as without the feed. It needs only
MPIMeasurements.

LiveFieldFeed.startDemo() sends a synthetic field at the MagSphere positions instead, to try the
viewer without hardware.
=#
module LiveFieldFeed

using MPIMeasurements
using MPIMeasurements: MagSphereUDP, MagSphereUDPResult, PorridgeMagSphereMeasurementProtocol,
                       sensorPositions, MAGSPHERE_UDP_POSITIONS_MM
using MPIMeasurements.ThreadPools: @tspawnat
using Sockets
using Unitful

include("LiveFieldPacket.jl")

const SettledFrame = Union{Nothing, Tuple{Int, MagSphereUDPResult}}   # (trigger index, frame)

mutable struct Feed
  task::Union{Task, Nothing}
  protocol::Union{PorridgeMagSphereMeasurementProtocol, Nothing}
  observer::Union{Function, Nothing}
  @atomic running::Bool
  @atomic sent::Int
  @atomic settled::SettledFrame       # newest settled frame, published by the observer
end

Feed() = Feed(nothing, nothing, nothing, true, 0, nothing)

"""
    start(protocol::PorridgeMagSphereMeasurementProtocol; framesPerConfiguration,
          settledFrames = max(1, framesPerConfiguration ÷ 10), status = i -> "",
          port, heartbeat_s = 1.0, thread = 2) -> Feed

Send the settled frame of every coil configuration (see the header) to the viewer on
127.0.0.1:`port`. Installs `protocol.frameObserver`; `stop!` removes it again. `status(i)`
is called on the feed's thread for every datagram with the trigger index `i` of the frame
sent (0 before the first one); its result is shown in the viewer's title, errors in it are
caught. Call after `init(protocol)` and before `execute`.
"""
function start(protocol::PorridgeMagSphereMeasurementProtocol; framesPerConfiguration::Integer,
               settledFrames::Integer = max(1, framesPerConfiguration ÷ 10),
               status::Function = i -> "", port::Integer = LIVE_FIELD_DEFAULT_PORT,
               heartbeat_s::Real = 1.0, thread::Integer = 2)
  framesPerConfiguration >= 1 || throw(ArgumentError("framesPerConfiguration must be at least 1"))
  1 <= settledFrames <= framesPerConfiguration ||
    throw(ArgumentError("settledFrames must be between 1 and framesPerConfiguration"))
  isnothing(protocol.frameObserver) ||
    throw(ArgumentError("The protocol already has a frame observer (a live field feed still running?)"))
  checkThread(thread)

  cam = getDevice(protocol.scanner, MagSphereUDP)
  positions = Float32.(ustrip.(u"m", sensorPositions(cam)))
  feed = Feed()
  feed.protocol = protocol
  feed.observer = settledFrameObserver(feed, Int(framesPerConfiguration), Int(settledFrames))
  protocol.frameObserver = feed.observer

  current() = begin
    s = @atomic feed.settled
    isnothing(s) && return 0, () -> LiveFieldPacket(0, 0, time(), zeros(Float32, 3, 0),
                                                     zeros(Float32, 3, 0), _status(status, 0))
    index, frame = s
    return index, () -> LiveFieldPacket(index, frame.timestamp, time(), positions,
                                        Float32.(ustrip.(u"T", frame.data)), _status(status, index))
  end
  feed.task = @tspawnat thread _run(feed, current, Int(port), Float64(heartbeat_s))
  return feed
end

"""
Observer for `protocol.frameObserver`: publishes in `feed.settled` the last frame of each
configuration that lies in its final `settledFrames` frames, once the configuration is over.
Runs on the protocol's thread, so it only keeps references, never copies or sends.
"""
function settledFrameObserver(feed::Feed, framesPerConfiguration::Int, settledFrames::Int)
  candidate = Ref{SettledFrame}(nothing)     # best frame so far of a configuration not yet over
  configuration(i) = (i - 1) ÷ framesPerConfiguration
  return function (index::Int, frame::MagSphereUDPResult)
    c = candidate[]
    if !isnothing(c) && configuration(c[1]) != configuration(index)
      # its configuration ended without its last frame (lost): the latest settled one stands in
      @atomic feed.settled = c
      candidate[] = nothing
    end
    position = (index - 1) % framesPerConfiguration + 1
    if position > framesPerConfiguration - settledFrames
      if position == framesPerConfiguration
        @atomic feed.settled = (index, frame)
        candidate[] = nothing
      else
        candidate[] = (index, frame)
      end
    end
    return nothing
  end
end

"""
    startDemo(; port, period_s = 1.0, thread = 2) -> Feed

Send a synthetic field at the MagSphere sensor positions every `period_s`: a gradient field
whose offset moves around, so the viewer can be checked without hardware.
"""
function startDemo(; port::Integer = LIVE_FIELD_DEFAULT_PORT, period_s::Real = 1.0, thread::Integer = 2)
  period_s > 0 || throw(ArgumentError("period_s must be positive"))
  checkThread(thread)
  positions = Float32.(MAGSPHERE_UDP_POSITIONS_MM .* 1e-3)
  t0 = time()
  current() = begin
    index = floor(Int, (time() - t0) / period_s) + 1
    return index, () -> begin
      t = (index - 1) * period_s
      offset = 2e-3 .* [sin(0.5t), cos(0.3t), sin(0.2t)]          # T
      field = similar(positions)
      for s in axes(positions, 2)
        x, y, z = positions[:, s]
        field[:, s] .= offset .+ [0.1x, 0.1y, -0.2z]                # 0.1 T/m selection-field-like gradient
      end
      LiveFieldPacket(index, UInt64(round(t * 1e6)), time(), positions, field,
                      "demo field, t = $(round(t, digits = 1)) s")
    end
  end
  feed = Feed()
  feed.task = @tspawnat thread _run(feed, current, Int(port), Float64(period_s))
  return feed
end

"Stop the feed, remove its observer from the protocol and wait up to 2 s for its task to end."
function stop!(feed::Feed)
  @atomic feed.running = false
  p = feed.protocol
  if !isnothing(p) && p.frameObserver === feed.observer
    p.frameObserver = nothing
  end
  isnothing(feed.task) || timedwait(() -> istaskdone(feed.task), 2.0)
  return feed
end

function checkThread(thread)
  2 <= thread <= Threads.nthreads(:default) + Threads.nthreads(:interactive) ||
    throw(ArgumentError("The live field feed runs on a worker thread so Ctrl+C keeps reaching the " *
      "main loop; thread $thread is not available. Start Julia with at least 2 threads (-t 4)."))
end

"""
Send loop. `current()` returns `(index, makePacket)` for the newest frame; a datagram goes out
when the index changes and otherwise every `heartbeat_s`.
"""
function _run(feed::Feed, current::Function, port::Int, heartbeat_s::Float64)
  sock = UDPSocket()
  warned = false
  sentIndex = -1
  sentAt = 0.0
  try
    while @atomic feed.running
      index, makePacket = current()
      if index != sentIndex || time() - sentAt >= heartbeat_s
        try
          send(sock, ip"127.0.0.1", port, encodeLiveFieldPacket(makePacket()))
          @atomic feed.sent += 1
        catch e
          # A missing receiver can surface as a send error on some systems; never stop for it
          warned || @warn "Live field feed: sending failed, continuing (further failures are not reported)" exception = e
          warned = true
        end
        sentIndex = index
        sentAt = time()
      end
      sleep(0.05)
    end
  finally
    close(sock)
  end
end

function _status(status::Function, index::Int)
  try
    return string(status(index))
  catch e
    return "status failed: $(sprint(showerror, e))"
  end
end

end # module
