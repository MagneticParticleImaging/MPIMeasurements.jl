# Export new frequency filtering buffers
export PeriodGroupingBuffer, RFFTBuffer

mutable struct AverageBuffer{T} <: IntermediateBuffer where {T<:Number}
  target::StorageBuffer
  buffer::Array{T,4}
  setIndex::Int
end
AverageBuffer(buffer::StorageBuffer, samples, channels, periods, avgFrames) = AverageBuffer{Float32}(buffer, zeros(Float32, samples, channels, periods, avgFrames), 1)
AverageBuffer(buffer::StorageBuffer, sequence::Sequence) = AverageBuffer(buffer, rxNumSamplesPerPeriod(sequence), length(rxChannels(sequence)), acqNumPeriodsPerFrame(sequence), acqNumFrameAverages(sequence))
function push!(avgBuffer::AverageBuffer{T}, frames::AbstractArray{T,4}) where {T<:Number}
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
    avgBuffer.buffer[:, :, :, avgBuffer.setIndex:toAvg] = @view frames[:, :, :, fr:toFrames]
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
mutable struct FrameBuffer{A<: AbstractArray{Float32, 4}} <: MeasurementBuffer
  nextFrame::Integer
  data::A
end
function FrameBuffer(sequence::Sequence)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  numChannel = length(rxChannels(sequence))
  @debug "Creating FrameBuffer with size $rxNumSamplingPoints x $numChannel x $numPeriods x $numFrames"
  buffer = zeros(Float32, rxNumSamplingPoints, numChannel, numPeriods, numFrames)
  return FrameBuffer(1, buffer)
end
function FrameBuffer(protocol::Protocol, file::String, sequence::Sequence)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  numChannel = length(rxChannels(sequence))
  return FrameBuffer(protocol, file, Float32, (rxNumSamplingPoints, numChannel, numPeriods, numFrames))
end
function FrameBuffer(protocol::Protocol, f::String, args...)
  @debug "Creating memory-mapped FrameBuffer with size $(args[2])"
  rm(file(protocol, f), force=true)
  mapped = mmap!(protocol, f, args...)
  return FrameBuffer(1, mapped)
end

function insert!(op, buffer::FrameBuffer, from::Integer, frames::AbstractArray{Float32, 4})
  to = from + size(frames, 4) - 1
  frames = op(frames, view(buffer.data, :, :, :, from:to))
  insert!(buffer, from, frames)
end
function insert!(buffer::FrameBuffer, from::Integer, frames::AbstractArray{Float32,4})
  to = from + size(frames, 4) - 1
  buffer.data[:, :, :, from:to] = frames
  buffer.nextFrame = to
  return to
end
function push!(buffer::FrameBuffer, frames::AbstractArray{Float32,4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return (start = from, stop = to)
end
read(buffer::FrameBuffer) = buffer.data
index(buffer::FrameBuffer) = buffer.nextFrame

abstract type FieldBuffer <: SequenceBuffer end
mutable struct DriveFieldBuffer{A <: AbstractArray{ComplexF64, 4}} <: FieldBuffer
  nextFrame::Integer
  data::A
  cont::ControlSequence
end
function insert!(op, buffer::DriveFieldBuffer, from::Integer, frames::AbstractArray{ComplexF64, 4})
  to = from + size(frames, 4) - 1
  frames = op(frames, view(buffer.data, :, :, :, from:to))
  insert!(buffer, from, frames)
end
function insert!(buffer::DriveFieldBuffer, from::Integer, frames::Array{ComplexF64,4})
  # TODO duplicate to FrameBuffer
  to = from + size(frames, 4) - 1
  buffer.data[:, :, :, from:to] = frames
  buffer.nextFrame = to
  return to
end
function push!(buffer::DriveFieldBuffer, frames::Array{ComplexF64,4})
  from = buffer.nextFrame
  to = insert!(buffer, from, frames)
  buffer.nextFrame = to + 1
  return (start = from, stop = to)
end
insert!(op, buffer::DriveFieldBuffer, from::Integer, frames::Array{Float32,4}) = insert!(op, buffer, from, calcFieldsFromRef(buffer.cont, frames))
insert!(buffer::DriveFieldBuffer, from::Integer, frames::Array{Float32,4}) = insert!(buffer, from, calcFieldsFromRef(buffer.cont, frames))
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
function insert!(buffer::FrameSplitterBuffer, from, frames)
  uMeas, uRef = retrieveMeasAndRef!(frames, buffer.daq)
  result = nothing
  if !isnothing(uMeas)
    for buf in buffer.targets
      measSinks = length(sinks(buf, MeasurementBuffer))
      fieldSinks = length(sinks(buf, DriveFieldBuffer))
      if measSinks > 0 && fieldSinks == 0
        # Return latest measurement result
        result = insert!(buf, from, uMeas)
      elseif measSinks == 0 && fieldSinks > 0
        insert!(buf, from, uRef)
      else
        @warn "Unexpected sink combination $(typeof.(sinks(buf)))"
      end
    end
  end
  return result
end
function insert!(op, buffer::FrameSplitterBuffer, from, frames)
  uMeas, uRef = retrieveMeasAndRef!(frames, buffer.daq)
  result = nothing
  if !isnothing(uMeas)
    for buf in buffer.targets
      measSinks = length(sinks(buf, MeasurementBuffer))
      fieldSinks = length(sinks(buf, DriveFieldBuffer))
      if measSinks > 0 && fieldSinks == 0
        # Return latest measurement result
        result = insert!(op, buf, from, uMeas)
      elseif measSinks == 0 && fieldSinks > 0
        insert!(op, buf, from, uRef)
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

mutable struct TemperatureBuffer{A <: AbstractArray{Float32, 2}} <: DeviceBuffer
  temperatures::A
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

mutable struct TxDAQControllerBuffer{A <: AbstractArray{ComplexF64, 4}} <: DeviceBuffer
  nextFrame::Integer
  applied::A
  tx::TxDAQController
end
function TxDAQControllerBuffer(tx::TxDAQController, sequence::ControlSequence)
  numFrames = acqNumFrames(sequence.targetSequence)
  numPeriods = acqNumPeriodsPerFrame(sequence.targetSequence)
  bufferShape = controlMatrixShape(sequence)
  buffer = zeros(ComplexF64, bufferShape[1], bufferShape[2], numPeriods, numFrames)
  return TxDAQControllerBuffer(1, buffer, tx)
end
update!(buffer::TxDAQControllerBuffer, start, stop) = insert!(buffer, calcControlMatrix(buffer.tx.cont), start, stop)
insert!(buffer::TxDAQControllerBuffer, applied::Matrix{ComplexF64}, start, stop) = buffer.applied[:, :, :, start:stop] .= applied
read(buffer::TxDAQControllerBuffer) = buffer.applied

mutable struct PeriodGroupingBuffer{T} <: IntermediateBuffer where {T<:Number}
  target::StorageBuffer
  numGrouping::Int
end
PeriodGroupingBuffer(buffer::StorageBuffer, numGrouping::Int) = PeriodGroupingBuffer{Float32}(buffer, numGrouping)

function push!(buffer::PeriodGroupingBuffer{T}, frames::AbstractArray{T,4}) where {T<:Number}
  if buffer.numGrouping == 1
    return push!(buffer.target, frames)
  end
  
  numSamples, numChannels, numPeriods, numFrames = size(frames)
  
  if mod(numPeriods, buffer.numGrouping) != 0
    error("Periods cannot be grouped: $numPeriods periods cannot be divided by $(buffer.numGrouping)")
  end
  
  tmp = permutedims(frames, (1, 3, 2, 4))
  newNumPeriods = div(numPeriods, buffer.numGrouping)
  tmp2 = reshape(tmp, numSamples * buffer.numGrouping, newNumPeriods, numChannels, numFrames)
  result = permutedims(tmp2, (1, 3, 2, 4))
  
  return push!(buffer.target, result)
end

sinks!(buffer::PeriodGroupingBuffer, sinks::Vector{SinkBuffer}) = sinks!(buffer.target, sinks)

mutable struct RFFTBuffer{T} <: IntermediateBuffer where {T<:Complex}
  target::StorageBuffer
  frequencyMask::Union{Vector{Int}, Nothing}
end
RFFTBuffer(buffer::StorageBuffer, frequencyMask::Union{Vector{Int}, Nothing} = nothing) = RFFTBuffer{ComplexF32}(buffer, frequencyMask)

function push!(buffer::RFFTBuffer{T}, frames::AbstractArray{<:Real,4}) where {T<:Complex}
  dataFD = rfft(frames, 1)
  result = isnothing(buffer.frequencyMask) ? dataFD : dataFD[buffer.frequencyMask, :, :, :]
  return push!(buffer.target, result)
end

sinks!(buffer::RFFTBuffer, sinks::Vector{SinkBuffer}) = sinks!(buffer.target, sinks)