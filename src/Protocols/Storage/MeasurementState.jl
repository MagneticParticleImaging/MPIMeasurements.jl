# Export buffer abstract types for testing and extension
export StorageBuffer, IntermediateBuffer, SinkBuffer, SequenceBuffer, DeviceBuffer

abstract type MeasurementState end

abstract type StorageBuffer end
abstract type IntermediateBuffer <: StorageBuffer end
abstract type SinkBuffer <: StorageBuffer end
abstract type SequenceBuffer <: SinkBuffer end
abstract type DeviceBuffer <: SinkBuffer end


abstract type AsyncBuffer <: IntermediateBuffer end

abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasType(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

sinks(buffer::StorageBuffer) = sinks!(buffer, SinkBuffer[])
function sinks(buffer::StorageBuffer, type::Type{T}) where {T<:SinkBuffer}
  return [sink for sink in sinks(buffer) if sink isa type]
end
function sink(buffer::StorageBuffer, type::Type{T}) where {T<:SinkBuffer}
  result = sinks(buffer, type)
  if length(result) == 0
    return nothing
  elseif length(result) == 1
    return result[1]
  else
    error("Cannot unambiguously retrieve a sink of type $type")
  end
end
sinks!(buffer::SinkBuffer, sinks::Vector{SinkBuffer}) = push!(sinks, buffer)

mutable struct SequenceMeasState <: MeasurementState
  numFrames::Int
  channel::Union{Channel, Nothing}
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  sequenceBuffer::StorageBuffer
  deviceBuffers::Union{Vector{DeviceBuffer}, Nothing}
  type::AsyncMeasTyp
end

mutable struct ProtocolMeasState <: MeasurementState
  measIsBg::Vector{Bool}
  buffers::Vector{Vector{SinkBuffer}}
end
ProtocolMeasState() = ProtocolMeasState(Vector{Bool}[], Vector{Vector{SinkBuffer}}[])
function push!(meas::ProtocolMeasState, buffers::Vector{SinkBuffer}; isBGMeas::Bool=false)
  push!(meas.buffers, buffers)
  push!(meas.measIsBg, isBGMeas)
end
function read(meas::ProtocolMeasState, type::Type{T}) where {T<:SinkBuffer}
  sinks = type[]
  for temp in meas.buffers
    for buffer in temp
      if buffer isa type
        push!(sinks, buffer)
      end
    end
  end
  if !isempty(sinks)
    results = read.(sinks)
    return cat(results..., dims=ndims(results[1]))
  else
    return nothing
  end
end
function measIsBGFrame(meas::ProtocolMeasState)
  isBGFrames = Bool[]
  for (i, buffers) in enumerate(meas.buffers)
    frames = Int64[]
    for buffer in buffers
      data = read(buffer)
      push!(frames, size(data, ndims(data)))
    end
    if length(unique(frames)) == 1
      temp = meas.measIsBg[i] ? ones(Bool, frames[1]) : zeros(Bool, frames[1])
      push!(isBGFrames, temp...)
    else
      throw(ErrorException("Different amount of frames for stored measurement step $frames"))
    end
  end
  return isBGFrames
end
function measIsBGFrame(meas::ProtocolMeasState, fgFrames, bgFrames)
  isBGFrames = Bool[]
  for isBG in meas.measIsBg
    frames = isBG ? ones(Bool, bgFrames) : zeros(Bool, fgFrames)
    push!(isBGFrames, frames...)
  end
  return isBGFrames
end
#### Scanner Measurement Functions ####
####  Async version  ####
SequenceMeasState() = SequenceMeasState(0, 1, nothing, nothing, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, nothing, RegularAsyncMeas())