abstract type MeasurementState end

abstract type StorageBuffer end
abstract type IntermediateBuffer <: StorageBuffer end
abstract type ResultBuffer <: StorageBuffer end
# Insertable-Trait for buffer? push!, insert! and read, index as interface

abstract type AsyncBuffer <: IntermediateBuffer end

abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasType(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

mutable struct AverageBuffer{T} <: IntermediateBuffer where {T<:Number}
  buffer::Array{T, 4}
  setIndex::Int
end
AverageBuffer(samples, channels, periods, avgFrames) = AverageBuffer{Float32}(zeros(Float32, samples, channels, periods, avgFrames), 1)

function push!(avgBuffer::AverageBuffer{T}, frames::Array{T, 4}) where {T<:Number}
  #setIndex - 1 = how many frames were written to the buffer

  # Compute how many frames there will be
  avgSize = size(avgBuffer.buffer)
  resultFrames = div(avgBuffer.setIndex - 1 + size(frames, 4), avgSize[4])

  result = nothing
  if resultFrames > 0
    result = zeros(T, avgSize[1], avgSize[2], avgSize[3], resultFrames)
  end

  setResult = 1
  fr = 1 
  while fr <= size(frames, 4)
    # How many left vs How many can fit into avgBuffer
    fit = min(size(frames, 4) - fr, avgSize[4] - avgBuffer.setIndex)
    
    # Insert into buffer
    toFrames = fr + fit 
    toAvg = avgBuffer.setIndex + fit 
    avgBuffer.buffer[:, :, :, avgBuffer.setIndex:toAvg] = frames[:, :, :, fr:toFrames]
    avgBuffer.setIndex += length(avgBuffer.setIndex:toAvg)
    fr = toFrames + 1
    
    # Average and add to result
    if avgBuffer.setIndex - 1 == avgSize[4]
      avgFrame = mean(avgBuffer.buffer, dims=4)[:,:,:,:]
      result[:, :, :, setResult] = avgFrame
      setResult += 1
      avgBuffer.setIndex = 1    
    end
  end

  return result
end

abstract type MeasurementBuffer <: ResultBuffer end
# TODO Error handling? Throw own error or crash with index error
# TODO read only return elements written to so far?
mutable struct SimpleFrameBuffer <: MeasurementBuffer
  nextFrame::Integer
  data::Array{Float32,4}
end
function SimpleFrameBuffer(sequence::Sequence)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  numChannel = length(rxChannels(sequence))
  buffer = zeros(Float32, rxNumSamplingPoints, numChannel, numPeriods, numFrames)
  return SimpleFrameBuffer(1, buffer)
end
function insert!(buffer::SimpleFrameBuffer, from::Integer, frames::Array{Float32,4})
  to = from + size(frames, 4) - 1
  buffer.data[:,:,:,from:to] = frames
  return to
end
function push!(buffer::SimpleFrameBuffer, frames::Array{Float32, 4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return buffer
end
read(buffer::SimpleFrameBuffer) = buffer.data
index(buffer::SimpleFrameBuffer) = buffer.nextFrame

mutable struct AveragedFrameBuffer <: MeasurementBuffer
  avgBuffer::AverageBuffer{Float32}
  simple::SimpleFrameBuffer
end
function AveragedFrameBuffer(sequence::Sequence)
  frameAverage = acqNumFrameAverages(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  numChannel = length(rxChannels(sequence))
  avgBuffer = AverageBuffer(rxNumSamplingPoints, numChannel, numPeriods, frameAverage)
  simple = SimpleFrameBuffer(sequence)
  return AveragedFrameBuffer(avgBuffer, simple)
end
function push!(buffer::AveragedFrameBuffer, frames::Array{Float32, 4})
  framesAvg = push!(buffer.avgBuffer, frames)
  if !isnothing(framesAvg)
    push!(buffer.simple, framesAvg)
  end
  return buffer
end
read(buffer::AveragedFrameBuffer) = read(buffer.simple)
index(buffer::AveragedFrameBuffer) = index(buffer.simple)

abstract type FieldBuffer <: ResultBuffer end
mutable struct SimpleFieldBuffer <: FieldBuffer
  nextFrame::Integer
  data::Array{ComplexF64, 4}
end
function insert!(buffer::SimpleFieldBuffer, from::Integer, frames::Array{ComplexF64, 4})
  # TODO duplicate to SimpleFrameBuffer
  to = from + size(frames, 4) - 1
  buffer.data[:,:,:,from:to] = frames
  return to
end
function push!(buffer::SimpleFieldBuffer, frames::Array{ComplexF64, 4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return buffer
end
push!(buffer::SimpleFieldBuffer, frames::Array{Float32, 4}) = push!(buffer, calcFieldsFromRef(buffer.cont, frames))
read(buffer::SimpleFieldBuffer) = buffer.data
index(buffer::SimpleFieldBuffer) = buffer.nextFrame


mutable struct AveragedFieldBuffer <: FieldBuffer
  avgBuffer::AverageBuffer{Float32}
  simple::SimpleFieldBuffer
end
function push!(buffer::AveragedFrameBuffer, frames::Array{Float32, 4})
  framesAvg = push!(buffer.avgBuffer, frames)
  if !isnothing(framesAvg)
    push!(buffer.simple, framesAvg)
  end
  return buffer
end
read(buffer::AveragedFrameBuffer) = read(buffer.simple)
index(buffer::AveragedFrameBuffer) = index(buffer.simple)


mutable struct SequenceMeasState <: MeasurementState
  numFrames::Int
  channel::Union{Channel, Nothing}
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  asyncBuffer::AsyncBuffer
  measBuffer::MeasurementBuffer
  #temperatures::Matrix{Float64} temps are not implemented atm
  # Reference data
  type::AsyncMeasTyp
end

#### Scanner Measurement Functions ####
####  Async version  ####
SequenceMeasState() = SequenceMeasState(0, 1, nothing, nothing, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, nothing, RegularAsyncMeas())