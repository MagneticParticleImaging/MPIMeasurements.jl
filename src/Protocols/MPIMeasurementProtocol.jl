export MPIMeasurementProtocol, MPIMeasurementProtocolParams

Base.@kwdef struct MPIMeasurementProtocolParams <: ProtocolParams
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
  "Foreground frames to measure. Overwrites sequence frames"
  fgFrames::Int64 = 1
  "Background frames to measure. Overwrites sequence frames"
  bgFrames::Int64 = 1
  "If unset no background measurement will be taken"
  measureBackground::Bool = true
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MPIMeasurementProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  executeTask::Union{Task, Nothing} = nothing

  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  restart::Bool = false
end

function _init(protocol::MPIMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.bgMeas = zeros(Float32,0,0,0,0)
end

function _execute(protocol::MPIMeasurementProtocol)
  @info "Measurement protocol started"


  while true
    protocol.restart = false
    performMeasurement(protocol)

    put!(protocol.biChannel, FinishedNotificationEvent())
    while !(protocol.finishAcknowledged || protocol.restart)
      handleEvents(protocol) 
      protocol.cancelled && throw(CancelException())
      sleep(0.05)  
    end
    !protocol.finishAcknowledged || break
    protocol.restart && put!(protocol.biChannel, OperationSuccessfulEvent(RestartEvent()))
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function performMeasurement(protocol::MPIMeasurementProtocol)
  if length(protocol.bgMeas) == 0 && protocol.params.measureBackground
    message = "No background measurement was taken\nShould one be measured now?"
    if askConfirmation(protocol, message)
      acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)
      measurement(protocol)
      protocol.bgMeas = protocol.scanner.seqMeasState.buffer
    end
  end

  acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)
  measurement(protocol)
end

function measurement(protocol::MPIMeasurementProtocol)
  # Start async measurement
  scanner = protocol.scanner
  measState = asyncMeasurement(scanner, protocol.params.sequence)
  producer = measState.producer
  consumer = measState.consumer
  
  # Handle events
  while !istaskdone(consumer)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
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


function cleanup(protocol::MPIMeasurementProtocol)
  # NOP
end

function stop(protocol::MPIMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(StopEvent()))
end

function resume(protocol::MPIMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MPIMeasurementProtocol)
  protocol.cancelled = true
  put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::MPIMeasurementProtocol, event::RestartEvent)
  protocol.restart = true
end

function handleEvent(protocol::MPIMeasurementProtocol, event::DataQueryEvent)
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


function handleEvent(protocol::MPIMeasurementProtocol, event::ProgressQueryEvent)
  framesTotal = protocol.scanner.seqMeasState.numFrames
  framesDone = min(protocol.scanner.seqMeasState.nextFrame - 1, framesTotal)
  put!(protocol.biChannel, ProgressEvent(framesDone, framesTotal, "Frames", event))
end

handleEvent(protocol::MPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MPIMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
  store = event.datastore
  scanner = protocol.scanner
  params = event.params
  data = protocol.scanner.seqMeasState.buffer
  bgdata = nothing
  if length(protocol.bgMeas) > 0
    bgdata = protocol.bgMeas
  end
  filename = saveasMDF(store, scanner, protocol.params.sequence, data, params, bgdata = bgdata)
  @show filename
  put!(protocol.biChannel, StorageSuccessEvent())
end