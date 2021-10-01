export AsyncMeasurementProtocol, AsyncMeasurementProtocolParams

Base.@kwdef mutable struct AsyncMeasurementProtocolParams <: ProtocolParams
  eventInterval::typeof(1.0u"s")
  sequence::Union{Sequence, Nothing} = nothing
end
function AsyncMeasurementProtocolParams(dict::Dict, scanner::MPIScanner) 
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(AsyncMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end
Base.@kwdef mutable struct AsyncMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::AsyncMeasurementProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  executeTask::Union{Task, Nothing} = nothing
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
end

function init(protocol::AsyncMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function _execute(protocol::AsyncMeasurementProtocol)
  @info "Measurement protocol started"
  
  if !isnothing(protocol.params.sequence)
    measurement(protocol)
  end

  put!(protocol.biChannel, FinishedNotificationEvent())
  while !protocol.finishAcknowledged
    handleEvents(protocol) 
    protocol.cancelled && throw(CancelException())
    sleep(0.01)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function measurement(protocol::AsyncMeasurementProtocol)
  # Start async measurement
  scanner = protocol.scanner
  measState = asyncMeasurement(scanner, protocol.params.sequence)
  producer = measState.producer
  consumer = measState.consumer
  
  # Handle events
  while !istaskdone(consumer)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(ustrip(u"s", protocol.params.eventInterval))
  end

  # Check tasks
  if Base.istaskfailed(producer)
    @error "Producer failed"
    stack = Base.catch_stack(producer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
  end
  if  Base.istaskfailed(consumer)
    @error "Consumer failed"
    stack = Base.catch_stack(consumer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
  end
end


function cleanup(protocol::AsyncMeasurementProtocol)
  # NOP
end

function stop(protocol::AsyncMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent())
end

function resume(protocol::AsyncMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent())
end

function cancel(protocol::AsyncMeasurementProtocol)
  protocol.cancelled = true
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::AsyncMeasurementProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURRFRAME"
    data = max(protocol.scanner.seqMeasState.nextFrame - 1, 0)
  elseif startswith(event.message, "FRAME")
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.scanner.seqMeasState.numFrames
        data = protocol.scanner.seqMeasState.buffer[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER"
    data = protocol.scanner.seqMeasState.buffer
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
    return
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end


function handleEvent(protocol::AsyncMeasurementProtocol, event::ProgressQueryEvent)
  framesTotal = protocol.scanner.seqMeasState.numFrames
  framesDone = min(protocol.scanner.seqMeasState.nextFrame - 1, framesTotal)
  put!(protocol.biChannel, ProgressEvent(framesDone, framesTotal, "Frames", event))
end

handleEvent(protocol::AsyncMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

#function handleEvent(protocol::AsyncMeasurementProtocol, event::StopEvent) 