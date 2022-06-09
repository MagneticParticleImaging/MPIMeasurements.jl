export RobotMPIMeasurementProtocol, RobotMPIMeasurementProtocolParams
"""
Parameters for the RobotMPIMeasurementProtocol
"""
Base.@kwdef mutable struct RobotMPIMeasurementProtocolParams <: ProtocolParams
  "Foreground position"
  fgPos::Union{ScannerCoords, Nothing} = nothing
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
function RobotMPIMeasurementProtocolParams(dict::Dict, scanner::MPIScanner) 
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(RobotMPIMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end
RobotMPIMeasurementProtocolParams(dict::Dict) = params_from_dict(RobotMPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct RobotMPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::RobotMPIMeasurementProtocolParams
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  executeTask::Union{Task, Nothing} = nothing

  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
end

function requiredDevices(protocol::RobotMPIMeasurementProtocol)
  result = [AbstractDAQ, Robot]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::RobotMPIMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  if isnothing(protocol.params.fgPos)
    throw(IllegalStateException("Protocol requires a foreground position"))
  end
  if !checkPositions(protocol)
    throw(IllegalStateException("Protocol has an illegal foreground position"))
  end

  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
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
end

function checkPositions(protocol::RobotMPIMeasurementProtocol)
  rob = getRobot(protocol.scanner)
  valid = true
  if hasDependency(rob, AbstractCollisionModule)
    cms = dependencies(rob, AbstractCollisionModule)
    for cm in cms
      valid &= all(checkCoords(cm, protocol.params.fgPos))
    end
  end
  valid &= checkAxisRange(rob, toRobotCoords(rob, protocol.params.fgPos))
  return valid
end

function timeEstimate(protocol::RobotMPIMeasurementProtocol)
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

function enterExecute(protocol::RobotMPIMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
end

function _execute(protocol::RobotMPIMeasurementProtocol)
  @info "Measurement protocol started"
  if !isReferenced(getRobot(protocol.scanner))
    throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  end

  performMeasurement(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())
  while !(protocol.finishAcknowledged)
    handleEvents(protocol) 
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function performMeasurement(protocol::RobotMPIMeasurementProtocol)
  rob = getRobot(protocol.scanner)
  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken. Continue will result in the robot moving!", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    moveAbs(rob, namedPosition(robot, "park"))
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)
    measurement(protocol)
    protocol.bgMeas = protocol.scanner.seqMeasState.buffer
    if askChoices(protocol, "Press continue when foreground measurement can be taken. Continue will result in the robot moving!", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end    
  end

  moveAbs(rob, protocol.params.fgPos)
  acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)
  measurement(protocol)
end

function measurement(protocol::RobotMPIMeasurementProtocol)
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

function asyncMeasurement(protocol::RobotMPIMeasurementProtocol)
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


function cleanup(protocol::RobotMPIMeasurementProtocol)
  # NOP
end

function stop(protocol::RobotMPIMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(StopEvent()))
end

function resume(protocol::RobotMPIMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::RobotMPIMeasurementProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::RobotMPIMeasurementProtocol, event::DataQueryEvent)
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


function handleEvent(protocol::RobotMPIMeasurementProtocol, event::ProgressQueryEvent)
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

handleEvent(protocol::RobotMPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::RobotMPIMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
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
