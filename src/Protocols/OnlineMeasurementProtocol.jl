export OnlineMeasurementProtocol, OnlineMeasurementProtocolParams

Base.@kwdef struct OnlineMeasurementProtocolParams <: ProtocolParams
  eventInterval::typeof(1.0u"s")
end
OnlineMeasurementProtocolParams(dict::Dict) = params_from_dict(OnlineMeasurementProtocolParams, dict)

Base.@kwdef mutable struct OnlineMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::OnlineMeasurementProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
end

function init(protocol::OnlineMeasurementProtocol)
  return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function execute(protocol::OnlineMeasurementProtocol)
  @info "Measurement protocol started"
  
  if !isnothing(protocol.scanner.currentSequence)
    measurement(protocol)
  end

  put!(protocol.biChannel, FinishedNotificationEvent())
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    if protocol.cancelled
      close(protocol.biChannel)
      return
    end
    sleep(0.01)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function measurement(protocol::OnlineMeasurementProtocol)
  # Start async measurement
  scanner = protocol.scanner
  measState = asyncMeasurement(scanner)
  producer = measState.producer
  consumer = measState.consumer
  
  # Handle events
  while !istaskdone(consumer)
    handleEvents(protocol)
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


function cleanup(protocol::OnlineMeasurementProtocol)
  # NOP
end

function stop(protocol::OnlineMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent())
end

function resume(protocol::OnlineMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent())
end

function cancel(protocol::OnlineMeasurementProtocol)
  protocol.cancelled = true
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::OnlineMeasurementProtocol, event::DataQueryEvent)
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


function handleEvent(protocol::OnlineMeasurementProtocol, event::ProgressQueryEvent)
  framesTotal = protocol.scanner.seqMeasState.numFrames
  framesDone = min(protocol.scanner.seqMeasState.nextFrame - 1, framesTotal)
  put!(protocol.biChannel, ProgressEvent(framesDone, framesTotal, "Frames", event))
end

handleEvent(protocol::OnlineMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

#function handleEvent(protocol::OnlineMeasurementProtocol, event::StopEvent) 