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
  measureBackground::Bool = false
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

  "Number of periods per offset of the MPS offset measurement. Overwrites parts of the sequence definition."
  dfPeriodsPerOffset::Integer = 2
  "If true all periods per offset are averaged"
  averagePeriodsPerOffset::Bool = true
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
  patchPermutation::Vector{Union{Int64, Nothing}} = Union{Int64, Nothing}[]
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

    # For each patch assign nothing if invalid or otherwise index in "proper" frame
    temp = Vector{Union{Int64, Nothing}}(nothing, acqNumPeriodsPerFrame(seq))
    if !protocol.params.sortPatches
      perm = filter(in(perm), 1:acqNumPeriodsPerFrame(seq))
    end
    # Same target for all frames to be averaged
    part = protocol.params.averagePeriodsPerOffset ? protocol.params.dfPeriodsPerOffset : 1
    for (i, patches) in enumerate(Iterators.partition(perm, part))
      temp[patches] .= i
    end

    protocol.sequence = seq
    protocol.patchPermutation = temp
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
  sequence, protocol.seqMeasState = SequenceMeasState(protocol)
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
end

function SequenceMeasState(protocol::MPSMeasurementProtocol)
  sequence = protocol.sequence
  daq = getDAQ(scanner(protocol))
  deviceBuffer = DeviceBuffer[]


  # Setup everything as defined per sequence
  if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
    push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
  end
  setup(daq, sequence)
  
  # Now for the buffer chain we want to reinterpret periods to frames
  # This has to happen after the RedPitaya sequence is set, as that code repeats the full sequence for each frame
  acqNumFrames(protocol.sequence, acqNumFrames(protocol.sequence) * periodsPerFrame(daq.rpc))
  setupRx(daq, daq.decimation, samplesPerPeriod(daq.rpc), 1)

  numFrames = acqNumFrames(protocol.sequence)

  # Prepare buffering structures:
  # RedPitaya-> MPSBuffer -> Splitter --> FrameBuffer{Mmap}
  #                                   |-> DriveFieldBuffer 
  @debug "Allocating buffer for $numFrames frames"
  numValidPatches = length(filter(x->!isnothing(x), protocol.patchPermutation))
  averages = protocol.params.averagePeriodsPerOffset ? protocol.params.dfPeriodsPerOffset : 1
  numFrames = div(numValidPatches, averages)
  bufferSize = (rxNumSamplingPoints(protocol.sequence), length(rxChannels(protocol.sequence)), 1, numFrames)
  buffer = FrameBuffer(protocol, "meas.bin", Float32, bufferSize)

  buffers = StorageBuffer[buffer]

  if protocol.params.controlTx
    len = length(keys(sequence.simpleChannel))
    push!(buffers, DriveFieldBuffer(1, zeros(ComplexF64, len, len, 1, numFrames), sequence))
  end

  buffer = FrameSplitterBuffer(daq, StorageBuffer[buffer])
  buffer = MPSBuffer(buffer, protocol.patchPermutation, numFrames, 1, acqNumPeriodsPerFrame(protocol.sequence))

  channel = Channel{channelType(daq)}(32)
  deviceBuffer = DeviceBuffer[]
  if protocol.params.saveTemperatureData
    push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner(protocol)), numFrames))
  end

  return sequence, SequenceMeasState(numFrames, channel, nothing, nothing, AsyncBuffer(buffer, daq), deviceBuffer, asyncMeasType(protocol.sequence))
end

mutable struct MPSBuffer <: IntermediateBuffer
  target::StorageBuffer
  permutation::Vector{Union{Int64, Nothing}}
  average::Int64
  counter::Int64
  total::Int64
end
function push!(mpsBuffer::MPSBuffer, frames::Array{T,4}) where T
  from = nothing
  to = nothing
  for i = 1:size(frames, 4)
    frameIdx = div(mpsBuffer.counter - 1, mpsBuffer.total)
    patchCounter = mod1(mpsBuffer.counter, mpsBuffer.total)
    patchIdx = mpsBuffer.permutation[patchCounter]
    if !isnothing(patchIdx)
      if mpsBuffer.average > 1
        to = insert!(+, mpsBuffer.target, frameIdx * mpsBuffer.total + patchIdx, view(frames, :, :, :, i:i)./mpsBuffer.average)
      else
        to = insert!(mpsBuffer.target, frameIdx * mpsBuffer.total + patchIdx, view(frames, :, :, :, i:i))
      end
    end
    mpsBuffer.counter += 1
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
  
  offsetPerm = zeros(Int64, size(data, 3))
  for (index, patch) in enumerate(protocol.patchPermutation)
    if !isnothing(patch)
      offsetPerm[patch] = index 
    end
  end
  offsets = protocol.offsetfields[offsetPerm, :]


  isBGFrame = reduce(&, reshape(measIsBGFrame(protocol.protocolMeasState), size(data, 3), :), dims = 1)[1, :]
  drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
  appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
  temperature = read(protocol.protocolMeasState, TemperatureBuffer)


  filename = nothing
  if protocol.params.saveAsSystemMatrix
    periodsPerOffset = protocol.params.averagePeriodsPerOffset ? 1 : protocol.params.dfPeriodsPerOffset
    isBGFrame = repeat(isBGFrame, inner = div(size(data, 3), periodsPerOffset))
    data = reshape(data, size(data, 1), size(data, 2), periodsPerOffset, :)
    # All periods in one frame (should) have same offset
    offsets = reshape(offsets, periodsPerOffset, :, size(offsets, 2))[1, :, :]
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