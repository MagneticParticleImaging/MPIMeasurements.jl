mutable struct AverageBuffer{T} <: IntermediateBuffer where {T<:Number}
  target::StorageBuffer
  buffer::Array{T,4}
  setIndex::Int
end
AverageBuffer(buffer::StorageBuffer, samples, channels, periods, avgFrames) = AverageBuffer{Float32}(buffer, zeros(Float32, samples, channels, periods, avgFrames), 1)
AverageBuffer(buffer::StorageBuffer, sequence::Sequence) = AverageBuffer(buffer, rxNumSamplesPerPeriod(sequence), length(rxChannels(sequence)), acqNumPeriodsPerFrame(sequence), acqNumFrameAverages(sequence))
function push!(avgBuffer::AverageBuffer{T}, frames::Array{T,4}) where {T<:Number}
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
      avgFrame = mean(avgBuffer.buffer, dims=4)[:, :, :, :]
      result[:, :, :, setResult] = avgFrame
      setResult += 1
      avgBuffer.setIndex = 1
    end
  end

  if !isnothing(result)
    return push!(avgBuffer.target, result)
  else
    return nothing
  end
end
sinks!(buffer::AverageBuffer, sinks::Vector{SinkBuffer}) = sinks!(buffer.target, sinks)

abstract type MeasurementBuffer <: SequenceBuffer end
# TODO Error handling? Throw own error or crash with index error
mutable struct SimpleFrameBuffer <: MeasurementBuffer
  nextFrame::Integer
  data::AbstractArray{Float32,4}
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
  buffer.data[:, :, :, from:to] = frames
  return to
end
function push!(buffer::SimpleFrameBuffer, frames::Array{Float32,4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return (start = from, stop = to)
end
read(buffer::SimpleFrameBuffer) = buffer.data
index(buffer::SimpleFrameBuffer) = buffer.nextFrame

abstract type FieldBuffer <: SequenceBuffer end
mutable struct DriveFieldBuffer <: FieldBuffer
  nextFrame::Integer
  data::Array{ComplexF64,4}
  cont::ControlSequence
end
function insert!(buffer::DriveFieldBuffer, from::Integer, frames::Array{ComplexF64,4})
  # TODO duplicate to SimpleFrameBuffer
  to = from + size(frames, 4) - 1
  buffer.data[:, :, :, from:to] = frames
  return to
end
function push!(buffer::DriveFieldBuffer, frames::Array{ComplexF64,4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return (start = from, stop = to)
end
push!(buffer::DriveFieldBuffer, frames::Array{Float32,4}) = push!(buffer, calcFieldsFromRef(buffer.cont, frames))
read(buffer::DriveFieldBuffer) = buffer.data
index(buffer::DriveFieldBuffer) = buffer.nextFrame

mutable struct FrameSplitterBuffer <: IntermediateBuffer
  daq::AbstractDAQ
  targets::Vector{StorageBuffer}
end
function push!(buffer::FrameSplitterBuffer, frames)
  uMeas, uRef = retrieveMeasAndRef!(frames, buffer.daq)
  result = nothing
  if !isnothing(uMeas)
    for buf in buffer.targets
      measSinks = length(sinks(buf, MeasurementBuffer))
      fieldSinks = length(sinks(buf, DriveFieldBuffer))
      if measSinks > 0 && fieldSinks == 0
        # Return latest measurement result
        result = push!(buf, uMeas)
      elseif measSinks == 0 && fieldSinks > 0
        push!(buf, uRef)
      else
        @warn "Unexpected sink combination $(typeof.(sinks(buf)))"
      end
    end
  end
  return result
end
function sinks!(buffer::FrameSplitterBuffer, sinks::Vector{SinkBuffer})
  for buf in buffer.targets
    sinks!(buf, sinks)
  end
  return sinks
end

mutable struct TemperatureBuffer <: DeviceBuffer
  temperatures::Matrix{Float32}
  sensor::TemperatureSensor
end
TemperatureBuffer(sensor::TemperatureSensor, numFrames::Int64) = TemperatureBuffer(zeros(Float32, numChannels(sensor), numFrames), sensor)
update!(buffer::TemperatureBuffer, start, stop) = insert!(buffer, getTemperatures(buffer.sensor), start, stop)
function insert!(buffer::TemperatureBuffer, temps::Vector{Float32}, start, stop)
  buffer.temperatures[:, start:stop] = temps
end
insert!(buffer::TemperatureBuffer, temps::Vector{Float64}, start, stop) = insert!(buffer, convert.(Float32, temps), start, stop)
insert!(buffer::TemperatureBuffer, temps::Vector{typeof(1.0u"°C")}, start, stop) = insert!(buffer, ustrip.(u"°C",temps), start, stop)
read(buffer::TemperatureBuffer) = buffer.temperatures