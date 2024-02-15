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
  "Sort patches"
  sortPatches::Bool = true
  "Flag if the measurement should be saved as a system matrix or not"
  saveAsSystemMatrix::Bool = true

  # TODO: This is only for 1D MPS systems for now
  "Number of periods per offset of the MPS offset measurement. Overwrites parts of the sequence definition."
  dfPeriodsPerOffset::Integer = 2
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

  sequence::Union{Sequence, Nothing} = nothing 
  offsetfields::Union{Matrix{Float64}, Nothing} = nothing
  patchPermutation::Vector{Int64} = Int64[]
  calibsize::Vector{Int64} = Int64[]

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
  #if isnothing(sequence(protocol))
  #  throw(IllegalStateException("Protocol requires a sequence"))
  #end
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

  try
    seq, perm, offsets, calibsize = prepareProtocolSequences(protocol.params.sequence, getDAQ(scanner(protocol)); numPeriodsPerPatch = protocol.params.dfPeriodsPerOffset)
    protocol.sequence = seq
    protocol.patchPermutation = perm
    protocol.offsetfields = ustrip.(u"T", offsets) # TODO make robust
    protocol.calibsize = calibsize
  catch e
    throw(e)
  end

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

function _execute(protocol::MPSMeasurementProtocol)
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
  sequence = protocol.sequence
  daq = getDAQ(scanner_)
  deviceBuffer = DeviceBuffer[]

  # Setup everything as defined per sequence
  setup(daq, sequence)
  # Now for the buffer chain we want to reinterpret periods to frames
  # This has to happen after the RedPitaya sequence is set, as that code repeats the full sequence for each frame
  acqNumFrames(sequence, acqNumFrames(sequence) * periodsPerFrame(daq.rpc))
  setupRx(daq, daq.decimation, samplesPerPeriod(daq.rpc), 1)

  #if protocol.params.controlTx
  #  sequence = controlTx(protocol.txCont, sequence)
  #  push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
  #end
    
  protocol.seqMeasState = SequenceMeasState(protocol)
  #if protocol.params.saveTemperatureData
  #  push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner_), acqNumFrames(protocol.params.sequence)))
  #end
  #protocol.seqMeasState.deviceBuffers = deviceBuffer
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
end

function SequenceMeasState(protocol::MPSMeasurementProtocol)
  sequence = protocol.sequence
  daq = getDAQ(scanner(protocol))

  numFrames = acqNumFrames(sequence)

  # Prepare buffering structures
  @debug "Allocating buffer for $numFrames frames"
  bufferSize = (rxNumSamplingPoints(sequence), length(rxChannels(sequence)), 1, length(protocol.patchPermutation))
  buffer = MmapFrameBuffer(protocol, "meas.bin", Float32, bufferSize)
  channel = Channel{channelType(daq)}(32)

  buffer = MPSBuffer(buffer, protocol.patchPermutation, 1, length(protocol.patchPermutation))
  
  deviceBuffer = DeviceBuffer[]
   if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
    push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
  end
  #if protocol.params.saveTemperatureData
  #  push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner_), acqNumFrames(protocol.params.sequence)))
  #end

  return SequenceMeasState(numFrames, channel, nothing, nothing, AsyncBuffer(buffer, daq), deviceBuffer, asyncMeasType(sequence))
end

mutable struct MPSBuffer <: IntermediateBuffer
  target::StorageBuffer
  permutation::Vector{Int64}
  counter::Int64
  total::Int64
end
function push!(mpsBuffer::MPSBuffer, frames::Array{T,4}) where T
  from = nothing
  to = nothing
  for i = 1:size(frames, 4)
    frameIdx = div(mpsBuffer.counter - 1, mpsBuffer.total) + 1
    patchCounter = mod1(mpsBuffer.counter, mpsBuffer.total)
    patchIdx = findfirst(x-> x == patchCounter, mpsBuffer.permutation)
    if !isnothing(from)
      to = insert!(target, frameIdx * mpsBuffer.total + patchIdx, frames[:, :, :, i])
      mpsBuffer.counter += 1
    end
  end
  if !isnothing(from) && !isnothing(to)
    return (start = from, stop = to)
  else
    return nothing
  end
end
sinks!(buffer::MPSBuffer, sinks::Vector{SinkBuffer}) = sinks!(buffer.target, sinks)


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
  sequence = protocol.sequence
  mdf = event.mdf

  data = read(protocol.protocolMeasState, MeasurementBuffer)
  data = reshape(data, rxNumSamplingPoints(sequence), length(rxChannels(sequence)), :, protocol.params.fgFrames + protocol.params.bgFrames * protocol.params.measureBackground)
  acqNumFrames(sequence, size(data, 4))
  
  offsets = protocol.offsetfields

  #if protocol.params.sortPatches
  #  data = data[:, :, protocol.patchPermutation, :]
  #  offsets = offsets[protocol.patchPermutation, :]
  #else
  #  # Just remove "dead" patches
  #  validPatches = filter(in(protocol.patchPermutation), collect(1:size(data, 3)))
  #  data = data[:, :, validPatches, :]
  #  offsets = offsets[validPatches, :]
  #end

  isBGFrame = measIsBGFrame(protocol.protocolMeasState)
  drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
  appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
  temperature = read(protocol.protocolMeasState, TemperatureBuffer)


  filename = nothing
  if protocol.params.saveAsSystemMatrix
    isBGFrame = repeat(isBGFrame, inner = div(size(data, 3), protocol.params.dfPeriodsPerOffset))
    data = reshape(data, size(data, 1), size(data, 2), protocol.params.dfPeriodsPerOffset, :)
    # All periods in one frame (should) have same offset
    offsets = reshape(offsets, protocol.params.dfPeriodsPerOffset, :, size(offsets, 2))[1, :, :]
    offsets = reshape(offsets, protocol.calibsize..., :) # make calib size "visible" to storing function
    filename = saveasMDF(store, scanner, sequence, data, offsets, isBGFrame, mdf, storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, drivefield = drivefield, temperatures = temperature, applied = appliedField)
  else
    filename = saveasMDF(store, scanner, sequence, data, isBGFrame, mdf, drivefield = drivefield, temperatures = temperature, applied = appliedField)
  end
  @info "The measurement was saved at `$filename`."
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MPSMeasurementProtocol) = Interactive()
protocolMDFStudyUse(protocol::MPSMeasurementProtocol) = UsingMDFStudy()

sequence(protocol::MPSMeasurementProtocol) = protocol.sequence