abstract type AbstractMPSProtocol <: Protocol end


function generateMPSSequence(sequence::Sequence, daq::AbstractDAQ; numPeriodsPerOffset = 1, sortPatches = true, averagePeriodsPerOffset = true)
  seq, perm, offsets, calibsize, numPeriodsPerFrame = prepareProtocolSequences(sequence, daq; numPeriodsPerOffset = numPeriodsPerOffset)

  # For each patch assign nothing if invalid or otherwise index in "proper" frame
  patchPerm = Vector{Union{Int64, Nothing}}(nothing, numPeriodsPerFrame)
  if !sortPatches
    # perm is arranged in a way that the first offset dimension switches the fastest
    # if the patches should be saved in the order they were measured, we need to sort perm
    perm = sort(perm)
  end
   
  # patchPerm contains the "target" for every patch that is measured, nothing for discarded patches, different indizes for non-averaged patches, identical indizes for averaged-patches
  # Same target for all frames to be averaged
  part = averagePeriodsPerOffset ? numPeriodsPerOffset : 1
  for (i, patches) in enumerate(Iterators.partition(perm, part))
    patchPerm[patches] .= i
  end

  offsets = ustrip.(u"T", offsets)

  return seq, patchPerm, offsets, calibsize
end

function generateMPSBGSequence(sequence::Sequence; numBGFrames = 1, numPeriodsPerOffset = 1)
  cpy = deepcopy(sequence)

  for field in cpy
    offsetIds = map(id, channels(field, ProtocolOffsetElectricalChannel))
    for id_ in offsetIds
      delete!(field, id_)
    end
  end

  acqNumFrameAverages(cpy, numPeriodsPerOffset)
  acqNumFrames(cpy, numBGFrames)
  return cpy
end

mutable struct MPSBuffer <: IntermediateBuffer
  target::StorageBuffer
  permutation::Vector{Union{Int64, Nothing}}
  average::Int64
  counter::Int64
  limit::Int64
  stride::Int64
  MPSBuffer(target, perm, average, counter, limit) = new(target, perm, average, counter, limit, length(unique(filter(!isnothing, perm))))
end
function push!(mpsBuffer::MPSBuffer, frames::Array{T,4}) where T
  from = nothing
  to = nothing
  for i = 1:size(frames, 4)
    frameIdx = div(mpsBuffer.counter - 1, mpsBuffer.limit)
    patchCounter = mod1(mpsBuffer.counter, mpsBuffer.limit)
    patchIdx = mpsBuffer.permutation[patchCounter]
    if !isnothing(patchIdx)
      if mpsBuffer.average > 1
        to = insert!(+, mpsBuffer.target, frameIdx * mpsBuffer.stride + patchIdx, view(frames, :, :, :, i:i)./mpsBuffer.average)
      else
        to = insert!(mpsBuffer.target, frameIdx * mpsBuffer.stride + patchIdx, view(frames, :, :, :, i:i))
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


function SequenceMeasState(protocol::AbstractMPSProtocol, sequence::Sequence; patchPermutation, averages, txCont::Union{TxDAQController, Nothing} = nothing, saveTemperatureData::Bool = false, saveDriveFieldData::Bool = false)
  daq = getDAQ(scanner(protocol))
  deviceBuffer = DeviceBuffer[]


  # Setup everything as defined per sequence
  if !isnothing(txCont)
    sequence = controlTx(txCont, sequence)
    push!(deviceBuffer, TxDAQControllerBuffer(txCont, sequence))
  end
  setup(daq, sequence)
  
  # Now for the buffer chain we want to reinterpret periods to frames
  # This has to happen after the RedPitaya sequence is set, as that code repeats the full sequence for each frame
  oldFrames = acqNumFrames(sequence)
  acqNumFrames(sequence, acqNumFrames(sequence) * periodsPerFrame(daq.rpc))
  setupRx(daq, daq.decimation, samplesPerPeriod(daq.rpc), 1)

  # Prepare buffering structures:
  # RedPitaya-> MPSBuffer -> Splitter --> FrameBuffer{Mmap}
  #                                   |-> DriveFieldBuffer 
  numValidPatches = length(filter(x->!isnothing(x), protocol.patchPermutation))
  numFrames = div(numValidPatches, averages) * oldFrames
  bufferSize = (rxNumSamplingPoints(sequence), length(rxChannels(sequence)), 1, numFrames)
  buffer = FrameBuffer(protocol, "meas.bin", Float32, bufferSize)

  buffers = StorageBuffer[buffer]

  if !isnothing(txCont) && saveDriveFieldData
    len = length(keys(sequence.simpleChannel))
    push!(buffers, DriveFieldBuffer(1, zeros(ComplexF64, len, len, 1, numFrames), sequence))
  end

  buffer = FrameSplitterBuffer(daq, buffers)
  buffer = MPSBuffer(buffer, patchPermutation, numFrames, 1, acqNumPeriodsPerFrame(sequence))

  channel = Channel{channelType(daq)}(32)
  deviceBuffer = DeviceBuffer[]
  if saveTemperatureData
    push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner(protocol)), numFrames))
  end

  return sequence, SequenceMeasState(numFrames, channel, nothing, nothing, AsyncBuffer(buffer, daq), deviceBuffer, asyncMeasType(protocol.sequence))
end