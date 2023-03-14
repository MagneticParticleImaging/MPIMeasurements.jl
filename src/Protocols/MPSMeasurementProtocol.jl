export MPSMeasurementProtocol, MPSMeasurementProtocolParams
"""
Parameters for the MPSMeasurementProtocol
"""
Base.@kwdef mutable struct MPSMeasurementProtocolParams <: ProtocolParams
  "Foreground frames to measure. Overwrites sequence frames"
  fgFrames::Int64 = 1
  "Background frames to measure. Overwrites sequence frames"
  bgFrames::Int64 = 1
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = true
  "Remember background measurement"
  rememberBGMeas::Bool = false
  "Tracer that is being used for the measurement"
  #tracer::Union{Tracer, Nothing} = nothing
  "If the temperature should be safed or not"
  saveTemperatureData::Bool = false
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing

  # TODO: This is only for 1D MPS systems for now
  "Start value of the MPS offset measurement. Overwrites parts of the sequence definition."
  offsetStart::typeof(1.0u"T") = -0.012u"T"
  "Stop value of the MPS offset measurement. Overwrites parts of the sequence definition."
  offsetStop::typeof(1.0u"T") = 0.012u"T"
  "Number of values of the MPS offset measurement. Overwrites parts of the sequence definition."
  offsetNum::Integer = 101
  "Number of periods per offset of the MPS offset measurement. Overwrites parts of the sequence definition."
  dfPeriodsPerOffset::Integer = 100
  "Number of periods per offset which should be deleted. Acquired total number of periods is `dfPeriodsPerOffset + deletedDfPeriodsPerOffset`. Overwrites parts of the sequence definition."
  deletedDfPeriodsPerOffset::Integer = 1
end
function MPSMeasurementProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence_ = nothing
  if haskey(dict, "sequence")
    sequence_ = Sequence(scanner, dict["sequence"])
    delete!(dict, "sequence")
  end
  
  params = params_from_dict(MPSMeasurementProtocolParams, dict)
  params.sequence = sequence_

  # TODO: Move to somewhere where it is used after setting the values in the GUI
  # if haskey(dict, "Tracer")
  #   tracer = MPIMeasurements.Tracer(;[Symbol(key) => tryuparse(value) for (key, value) in dict["Tracer"]]...)
  #   delete!(dict, "Tracer")
  # else
  #   tracer = Tracer()
  # end

  #params.tracer = tracer

  return params
end
MPSMeasurementProtocolParams(dict::Dict) = params_from_dict(MPSMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPSMeasurementProtocol <: Protocol
  @add_protocol_fields MPSMeasurementProtocolParams

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

function requiredDevices(protocol::MPSMeasurementProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::MPSMeasurementProtocol)
  if isnothing(sequence(protocol))
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
  protocol.bgMeas = zeros(Float32,0,0,0,0)
  protocol.protocolMeasState = ProtocolMeasState()

  setupSequence(protocol)

  return nothing
end

function timeEstimate(protocol::MPSMeasurementProtocol)
  est = "Unknown"
  if !isnothing(sequence(protocol))
    params = protocol.params
    seq = params.sequence
    totalFrames = (params.fgFrames + params.bgFrames) * acqNumFrameAverages(seq)
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
    @info "The estimated duration is $est s."
  end
  return est
end

function enterExecute(protocol::MPSMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
end

function getRelevantDfDivider(protocol::MPSMeasurementProtocol)
  sequence_ = sequence(protocol)

  divider = nothing
  offsetFieldIdx = nothing
  offsetChannelIdx = nothing
  for (fieldIdx, field) in enumerate(fields(sequence_))
    for (channelIdx, channel) in enumerate(channels(field))
      if channel isa PeriodicElectricalChannel
        @warn "The protocol currently always uses the first component of $(id(channel)) for determining the divider."
        divider = channel.components[1].divider
      elseif channel isa ContinuousElectricalChannel
        offsetFieldIdx = fieldIdx
        offsetChannelIdx = channelIdx
      end
    end
  end

  if isnothing(divider)
    throw(ProtocolConfigurationError("The sequence `$(name(sequence_))` for the protocol `$(name(protocol))` does not define a PeriodicElectricalChannel and thus a divider."))
  end

  if isnothing(offsetFieldIdx) || isnothing(offsetChannelIdx)
    throw(ProtocolConfigurationError("The sequence `$(name(sequence_))` for the protocol `$(name(protocol))` does not define a ContinuousElectricalChannel and thus an offset field description."))
  end

  return divider, offsetFieldIdx, offsetChannelIdx
end

function createOffsetChannel(protocol::MPSMeasurementProtocol; deletedPeriodsPerOffset=protocol.params.deletedDfPeriodsPerOffset)
  sequence_ = sequence(protocol)

  divider, offsetFieldIdx, offsetChannelIdx = getRelevantDfDivider(protocol)

  stepDivider = divider * (protocol.params.dfPeriodsPerOffset + deletedPeriodsPerOffset)
  offsetDivider = stepDivider * protocol.params.offsetNum

  chanOffset = (protocol.params.offsetStop + protocol.params.offsetStart) / 2
  amplitude = abs(protocol.params.offsetStop - protocol.params.offsetStart) / 2
  
  oldChannel = sequence_.fields[offsetFieldIdx].channels[offsetChannelIdx]
  newChannel = ContinuousElectricalChannel(id=oldChannel.id, dividerSteps=stepDivider, divider=offsetDivider, amplitude=amplitude, phase=oldChannel.phase, offset=chanOffset, waveform=WAVEFORM_SAWTOOTH_RISING)

  @info "Values used for the creation of the offset channel" divider stepDivider offsetDivider chanOffset amplitude

  return newChannel, offsetFieldIdx, offsetChannelIdx
end

function setupSequence(protocol::MPSMeasurementProtocol; deletedPeriodsPerOffset=protocol.params.deletedDfPeriodsPerOffset)
  sequence_ = sequence(protocol)
  newChannel, offsetFieldIdx, offsetChannelIdx = createOffsetChannel(protocol, deletedPeriodsPerOffset=deletedPeriodsPerOffset)
  
  @info "Offset values used for the measurement" MPIMeasurements.values(newChannel)
  
  sequence_.fields[offsetFieldIdx].channels[offsetChannelIdx] = newChannel
  protocol.params.sequence = sequence_
end

function _execute(protocol::MPSMeasurementProtocol)
  @debug "Measurement protocol started"

  setupSequence(protocol)
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

function performMeasurement(protocol::MPSMeasurementProtocol)
  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    acqNumFrames(sequence(protocol), protocol.params.bgFrames)

    @debug "Taking background measurement."
    measurement(protocol)
    protocol.bgMeas = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))
    deviceBuffers = protocol.seqMeasState.deviceBuffers
    push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = true)
    if askChoices(protocol, "Press continue when foreground measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
  end

  @debug "Setting number of foreground frames."
  acqNumFrames(sequence(protocol), protocol.params.fgFrames)

  @debug "Starting foreground measurement."
  protocol.unit = "Frames"
  measurement(protocol)
  deviceBuffers = protocol.seqMeasState.deviceBuffers
  push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = false)
end

function measurement(protocol::MPSMeasurementProtocol)
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

function asyncMeasurement(protocol::MPSMeasurementProtocol)
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


function cleanup(protocol::MPSMeasurementProtocol)
  # NOP
end

function stop(protocol::MPSMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(StopEvent()))
end

function resume(protocol::MPSMeasurementProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MPSMeasurementProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::MPSMeasurementProtocol, event::DataQueryEvent)
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


function handleEvent(protocol::MPSMeasurementProtocol, event::ProgressQueryEvent)
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

handleEvent(protocol::MPSMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MPSMeasurementProtocol, event::DatasetStoreStorageRequestEvent)
  store = event.datastore
  scanner = protocol.scanner
  mdf = event.mdf
  data = read(protocol.protocolMeasState, MeasurementBuffer)

  if protocol.params.deletedDfPeriodsPerOffset > 0
    numSamples_ = size(data, 1)
    numChannels_ = size(data, 2)
    numPeriods_ = size(data, 3)
    numFrames_ = size(data, 4)

    numPeriodsPerOffset_ = div(numPeriods_, protocol.params.offsetNum)

    data = reshape(data, (numSamples_, numChannels_, numPeriodsPerOffset_, protocol.params.offsetNum, numFrames_))
    data = data[:, :, protocol.params.deletedDfPeriodsPerOffset+1:end, :, :] # Kick out first N periods
    data = reshape(data, (numSamples_, numChannels_, :, numFrames_))

    # Reset sequence since the info is used for the MDF
    setupSequence(protocol, deletedPeriodsPerOffset=0)
  end

  isBGFrame = measIsBGFrame(protocol.protocolMeasState)
  drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
  appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
  temperature = read(protocol.protocolMeasState, TemperatureBuffer)
  filename = saveasMDF(store, scanner, protocol.params.sequence, data, isBGFrame, mdf, drivefield = drivefield, temperatures = temperature, applied = appliedField)
  @info "The measurement was saved at `$filename`."
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MPSMeasurementProtocol) = Interactive()
protocolMDFStudyUse(protocol::MPSMeasurementProtocol) = UsingMDFStudy()

sequence(protocol::MPSMeasurementProtocol) = protocol.params.sequence