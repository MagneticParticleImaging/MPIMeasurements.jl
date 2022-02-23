export MechanicalMPIMeasurementProtocol, MechanicalMPIMeasurementProtocolParams
"""
Parameters for the MechanicalMPIMeasurementProtocol
"""
Base.@kwdef mutable struct MechanicalMPIMeasurementProtocolParams <: ProtocolParams
  "Foreground frames to measure. Overwrites sequence frames"
  fgFrames::Int64 = 1
  "Background frames to measure. Overwrites sequence frames"
  bgFrames::Int64 = 1
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = true
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
  "Remember background measurement"
  rememberBGMeas::Bool = false
end
function MechanicalMPIMeasurementProtocolParams(dict::Dict, scanner::MPIScanner) 
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(MechanicalMPIMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end
MechanicalMPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MechanicalMPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MechanicalMPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MechanicalMPIMeasurementProtocolParams
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  executeTask::Union{Task, Nothing} = nothing

  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
end

function requiredDevices(protocol::MechanicalMPIMeasurementProtocol)
  result = [MechanicsController]
  if hasElectricalTxChannels(protocol.params.sequence) # TODO: Acquisition is always needed... is it?
    push!(result, AbstractDAQ)
    if protocol.params.controlTx
      push!(result, TxDAQController)
    end
  end
  return result
end

function _init(protocol::MechanicalMPIMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx && hasElectricalTxChannels(protocol.params.sequence)
    controllers = getDevices(protocol.scanner, TxDAQController)
    if length(controllers) > 1
      throw(IllegalStateException("Cannot unambiguously find a TxDAQController as the scanner has $(length(controllers)) of them"))
    end
    protocol.txCont = controllers[1]
    protocol.txCont.currTx = nothing
  else
    protocol.txCont = nothing
  end
  protocol.bgMeas = zeros(Float32,0,0,0,0)

  return nothing
end

function timeEstimate(protocol::MechanicalMPIMeasurementProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence)
    params = protocol.params
    seq = params.sequence
    totalFrames = (params.fgFrames + params.bgFrames) * acqNumFrameAverages(seq)
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
    @show est
  end
  return est
end

function enterExecute(protocol::MechanicalMPIMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
end

function _execute(protocol::MechanicalMPIMeasurementProtocol)
  @info "Measurement protocol started"

  #performMeasurement(protocol) # Note: Uncommented for testing

  put!(protocol.biChannel, FinishedNotificationEvent())
  while !(protocol.finishAcknowledged)
    handleEvents(protocol) 
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function performMeasurement(protocol::MechanicalMPIMeasurementProtocol)
  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground
    @debug "Asking for background measurement."
    askChoices(protocol, "Press continue when background measurement can be taken", ["Continue"])

    @debug "Setting number of background frames."
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)

    @debug "Taking background measurement."
    measurement(protocol)
    protocol.bgMeas = protocol.scanner.seqMeasState.buffer

    askChoices(protocol, "Press continue when foreground measurement can be taken", ["Continue"])
  else
    @debug "No background measurement was selected."   
  end

  @debug "Setting number of foreground frames."
  acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)

  @debug "Starting foreground measurement."
  measurement(protocol)
end

function measurement(protocol::MechanicalMPIMeasurementProtocol)
  # Start async measurement
  protocol.measuring = true
  measState = asyncMeasurement(protocol)
  producer = measState.producer
  consumer = measState.consumer
  
  # Handle events
  while !istaskdone(consumer)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end
  protocol.measuring = false

  # Check tasks
  ex = nothing
  if Base.istaskfailed(producer)
    @error "Producer failed"
    stack = Base.catch_stack(producer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
    ex = stack[1]
  end
  if Base.istaskfailed(consumer)
    @error "Consumer failed"
    stack = Base.catch_stack(consumer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
    if isnothing(ex)
      ex = stack[1]
    end
  end
  if !isnothing(ex)
    throw(ErrorException("Measurement failed, see logged exceptions and stacktraces"))
  end

end

function asyncMeasurement(protocol::MechanicalMPIMeasurementProtocol)
  scanner = protocol.scanner
  sequence = protocol.params.sequence
  prepareAsyncMeasurement(scanner, sequence)
  if protocol.params.controlTx
    controlTx(protocol.txCont, sequence, protocol.txCont.currTx)
  end
  scanner.seqMeasState.producer = @tspawnat scanner.generalParams.producerThreadID asyncProducer(scanner.seqMeasState.channel, scanner, sequence, prepTx = !protocol.params.controlTx)
  bind(scanner.seqMeasState.channel, scanner.seqMeasState.producer)
  scanner.seqMeasState.consumer = @tspawnat scanner.generalParams.consumerThreadID asyncConsumer(scanner.seqMeasState.channel, scanner)
  return scanner.seqMeasState
end


function cleanup(protocol::MechanicalMPIMeasurementProtocol)
  # NOP
end

function stop(protocol::MechanicalMPIMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(StopEvent()))
end

function resume(protocol::MechanicalMPIMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MechanicalMPIMeasurementProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::MechanicalMPIMeasurementProtocol, event::DataQueryEvent)
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


function handleEvent(protocol::MechanicalMPIMeasurementProtocol, event::ProgressQueryEvent)
  reply = nothing
  if length(protocol.bgMeas) > 0 && !protocol.measuring
    reply = ProgressEvent(0, 1, "No bg meas", event)
  elseif !isnothing(protocol.scanner.seqMeasState) 
    framesTotal = protocol.scanner.seqMeasState.numFrames
    framesDone = min(protocol.scanner.seqMeasState.nextFrame - 1, framesTotal)
    reply = ProgressEvent(framesDone, framesTotal, "Frames", event)
  else 
    reply = ProgressEvent(0, 0, "N/A", event)  
  end
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::MechanicalMPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MechanicalMPIMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
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
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end
