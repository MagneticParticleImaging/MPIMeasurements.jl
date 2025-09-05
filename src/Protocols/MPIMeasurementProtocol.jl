export MPIMeasurementProtocol, MPIMeasurementProtocolParams
"""
Parameters for the `MPIMeasurementProtocol`
  
$FIELDS
"""
Base.@kwdef mutable struct MPIMeasurementProtocolParams <: ProtocolParams
  "Foreground frames to measure. Overwrites sequence frames"
  fgFrames::Int64 = 1
  "Background frames to measure. Overwrites sequence frames"
  bgFrames::Int64 = 1
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = true
  "If the temperature should be safed or not"
  saveTemperatureData::Bool = false
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
  "Do not measure background but reuse the last BG measurement if suitable"
  reuseLastBGMeas::Bool = false
end
function MPIMeasurementProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(MPIMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPIMeasurementProtocol <: Protocol
  @add_protocol_fields MPIMeasurementProtocolParams

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing
  protocolMeasState::Union{ProtocolMeasState, Nothing} = nothing
  
  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
end

function requiredDevices(protocol::MPIMeasurementProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  if protocol.params.saveTemperatureData
    push!(result, TemperatureSensor)
  end
  return result
end

function _init(protocol::MPIMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  protocol.protocolMeasState = ProtocolMeasState()
  return nothing
end

function timeEstimate(protocol::MPIMeasurementProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence)
    params = protocol.params
    seq = params.sequence
    totalFrames = (params.fgFrames + params.bgFrames*params.measureBackground*!params.reuseLastBGMeas) * acqNumFrameAverages(seq)
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
  end
  return est
end

function enterExecute(protocol::MPIMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.unit = ""
  protocol.protocolMeasState = ProtocolMeasState()
end

function _execute(protocol::MPIMeasurementProtocol)
  @debug "Measurement protocol started"

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

function performMeasurement(protocol::MPIMeasurementProtocol)
  if (length(protocol.bgMeas) == 0 || !protocol.params.reuseLastBGMeas) && protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)

    @debug "Taking background measurement."
    protocol.unit = "BG Frames"
    measurement(protocol)
    deviceBuffers = protocol.seqMeasState.deviceBuffers
    push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = true)
    protocol.bgMeas = read(protocol.protocolMeasState, MeasurementBuffer)
    if askChoices(protocol, "Press continue when foreground measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
  end

  @debug "Setting number of foreground frames."
  acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)

  @debug "Starting foreground measurement."
  protocol.unit = "Frames"
  measurement(protocol)
  deviceBuffers = protocol.seqMeasState.deviceBuffers
  push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = false)
end

function measurement(protocol::MPIMeasurementProtocol)
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

function asyncMeasurement(protocol::MPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  sequence = protocol.params.sequence
  daq = getDAQ(scanner_)
  deviceBuffer = DeviceBuffer[]
  if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
    push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
  end
  setup(daq, sequence)
  protocol.seqMeasState = SequenceMeasState(daq, sequence)
  if protocol.params.saveTemperatureData
    push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner_), acqNumFrames(protocol.params.sequence)))
  end
  protocol.seqMeasState.deviceBuffers = deviceBuffer
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
end

function cancel(protocol::MPIMeasurementProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::MPIMeasurementProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURRFRAME"
    data = max(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, 0)
  elseif startswith(event.message, "FRAME")
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.seqMeasState.numFrames
        data = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER"
    data = copy(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)))
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


function handleEvent(protocol::MPIMeasurementProtocol, event::ProgressQueryEvent)
  reply = nothing
  if !isnothing(protocol.seqMeasState)
    framesTotal = protocol.seqMeasState.numFrames
    framesDone = min(index(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, framesTotal)
    reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  else
    reply = ProgressEvent(0, 0, "N/A", event)
  end
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::MPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MPIMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
  store = event.datastore
  scanner = protocol.scanner
  mdf = event.mdf
  data = read(protocol.protocolMeasState, MeasurementBuffer)
  isBGFrame = measIsBGFrame(protocol.protocolMeasState)
  if protocol.params.reuseLastBGMeas
    try
      data = cat(data,protocol.bgMeas,dims=4)
      isBGFrame = cat(isBGFrame,trues(size(protocol.bgMeas,4)), dims=1)
    catch
      @error "The last BG measurement is not compatible with your current measurement, cant write BG into file! Data is size $(size(data)), BG is size $(size(protocol.bgMeas))"
    end
  end
  drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
  appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
  temperature = read(protocol.protocolMeasState, TemperatureBuffer)
  filename = saveasMDF(store, scanner, protocol.params.sequence, data, isBGFrame, mdf, drivefield = drivefield, temperatures = temperature, applied = appliedField)
  @info "The measurement was saved at `$filename`."
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MPIMeasurementProtocol) = Interactive()
protocolMDFStudyUse(protocol::MPIMeasurementProtocol) = UsingMDFStudy()
