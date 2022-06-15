export MechanicalMPIMeasurementProtocol, MechanicalMPIMeasurementProtocolParams
"""
Parameters for the MechanicalMPIMeasurementProtocol
"""
Base.@kwdef mutable struct MechanicalMPIMeasurementProtocolParams <: ProtocolParams
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

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing

  bgMeas::Array{Float32, 4} = zeros(Float32, 0, 0, 0, 0)
  steppedMeas::Vector{Array{Float32, 4}} = []
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  mechCont::Union{MechanicsController, Nothing} = nothing
end

function requiredDevices(protocol::MechanicalMPIMeasurementProtocol)
  result = [AbstractDAQ, MechanicsController]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end

  return result
end

function _init(protocol::MechanicalMPIMeasurementProtocol)
  @debug "Initializing protocol $(name(protocol))."
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
    protocol.txCont.currTx = nothing
  else
    protocol.txCont = nothing
  end

  if hasMechanicalTxChannels(protocol.params.sequence)
    @debug "The sequence has mechanical channels. Now setting them up."
    protocol.mechCont = getDevice(protocol.scanner, MechanicsController)
    setup(protocol.mechCont, protocol.params.sequence)
  end

  protocol.bgMeas = zeros(Float32, 0, 0, 0, 0)

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
  @debug "Mechanical measurement protocol started"

  performMeasurement(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function performMeasurement(protocol::MechanicalMPIMeasurementProtocol)
  # Clear possible old MPIMeasurements
  protocol.steppedMeas = []

  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)

    @debug "Taking background measurement."
    measurement(protocol)
    protocol.bgMeas = protocol.seqMeasState.buffer
    if askChoices(protocol, "Press continue when foreground measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
  end

  @debug "Setting number of foreground frames."
  acqNumFrames(protocol.params.sequence, 1) #TODO: Do we need to make this more flexible?

  @debug "Starting foreground measurement."

  mechCont = getDevice(scanner(protocol), MechanicsController)
  totalNumberOfSteps_ = totalNumberOfSteps(mechCont)
  for stepNumber in 1:totalNumberOfSteps_
    @info "Starting measurement step $stepNumber of $totalNumberOfSteps_."
    measurement(protocol)
    push!(protocol.steppedMeas, protocol.seqMeasState.buffer)
    doStep(mechCont)
  end
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
    currExceptions = current_exceptions(producer)
    @error "Producer failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
  end
  if Base.istaskfailed(consumer)
    currExceptions = current_exceptions(producer)
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

function asyncMeasurement(protocol::MechanicalMPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  sequence = protocol.params.sequence
  prepareAsyncMeasurement(protocol, sequence)
  if protocol.params.controlTx
    controlTx(protocol.txCont, sequence, protocol.txCont.currTx)
  end
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence, prepTx = !protocol.params.controlTx)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState.channel, protocol)
  return protocol.seqMeasState
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
    data = max(protocol.seqMeasState.nextFrame - 1, 0)
  elseif startswith(event.message, "FRAME")
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.seqMeasState.numFrames
      data = protocol.seqMeasState.buffer[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER"
    data = protocol.seqMeasState.buffer
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
  elseif !isnothing(protocol.seqMeasState)
    framesTotal = protocol.seqMeasState.numFrames
    framesDone = min(protocol.seqMeasState.nextFrame - 1, framesTotal)
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
  mdf = event.mdf

  measSize = collect(size(protocol.seqMeasState.buffer))
  measSize[4] = length(protocol.steppedMeas)
  data = Array{Float32, 4}(undef, Tuple(measSize))
  
  for (frameIdx, meas) in enumerate(protocol.steppedMeas)
    data[:, :, :, frameIdx] = meas # Note: Assumes one frame per measurement
  end

  @warn data

  bgdata = nothing
  if length(protocol.bgMeas) > 0
    bgdata = protocol.bgMeas
  end
  filename = saveasMDF(store, scanner, protocol.params.sequence, data, mdf, bgdata = bgdata)
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MechanicalMPIMeasurementProtocol) = Interactive()
protocolMDFStudyUse(protocol::MechanicalMPIMeasurementProtocol) = UsingMDFStudy()