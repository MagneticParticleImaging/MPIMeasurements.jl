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
  @add_protocol_fields RobotMPIMeasurementProtocolParams

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing

  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
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
  protocol.unit = ""
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
    enable(rob)
    moveAbs(rob, namedPosition(rob, "park"))
    disable(rob)
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)
    @debug "Taking background measurement."
    protocol.unit = "BG Frames"
    measurement(protocol)
    protocol.bgMeas = protocol.seqMeasState.buffer
    if askChoices(protocol, "Press continue when foreground measurement can be taken. Continue will result in the robot moving!", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end    
  end

  enable(rob)
  moveAbs(rob, protocol.params.fgPos)
  disable(rob)
  @debug "Starting foreground measurement."
  acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)
  protocol.unit = "Frames"
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
    currExceptions = current_exceptions(producer)
    @error "Producer failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
  end
  if Base.istaskfailed(consumer)
    currExceptions = current_exceptions(consumer)
    @error "Consumer failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    if isnothing(ex)
      ex = currExceptions[1][:exception]
    end
  end
  if !isnothing(ex)
    throw(ErrorException("Measurement failed, see logged exceptions and stacktraces"))
  end

end

function asyncMeasurement(protocol::RobotMPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  sequence = protocol.params.sequence
  daq = getDAQ(scanner_)
  if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
  end
  setup(daq, sequence)
  protocol.seqMeasState = SequenceMeasState(daq, sequence)
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState.channel, protocol)
  return protocol.seqMeasState
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
    data = max(protocol.seqMeasState.nextFrame - 1, 0)
  elseif startswith(event.message, "FRAME")
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.seqMeasState.numFrames
        data = protocol.seqMeasState.buffer[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER"
    data = copy(protocol.seqMeasState.buffer)
  elseif event.message == "BG"
    if length(protocol.bgMeas) > 0
      data = copy(protocol.bgMeas)
    else
      data = nothing
    end
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
    return
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end


function handleEvent(protocol::RobotMPIMeasurementProtocol, event::ProgressQueryEvent)
  reply = nothing
  if !isnothing(protocol.seqMeasState)
    framesTotal = protocol.seqMeasState.numFrames
    framesDone = min(protocol.seqMeasState.nextFrame - 1, framesTotal)
    reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  else
    reply = ProgressEvent(0, 0, "N/A", event)
  end
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::RobotMPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::RobotMPIMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
  store = event.datastore
  scanner = protocol.scanner
  mdf = event.mdf
  data = protocol.seqMeasState.buffer
  bgdata = nothing
  if length(protocol.bgMeas) > 0
    bgdata = protocol.bgMeas
  end
  filename = saveasMDF(store, scanner, protocol.params.sequence, data, mdf, bgdata = bgdata)
  @show filename
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end


protocolInteractivity(protocol::RobotMPIMeasurementProtocol) = Interactive()
protocolMDFStudyUse(protocol::RobotMPIMeasurementProtocol) = UsingMDFStudy()

