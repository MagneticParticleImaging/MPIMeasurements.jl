abstract type MeasurementState end

abstract type StorageBuffer end
abstract type IntermediateBuffer <: StorageBuffer end
abstract type SinkBuffer <: StorageBuffer end

abstract type AsyncBuffer <: IntermediateBuffer end

abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasType(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

sinks(buffer::StorageBuffer) = sinks(buffer, SinkBuffer[])
function sinks(buffer::StorageBuffer, type::Type{T}) where {T<:SinkBuffer}
  return [sink for sink in sinks(buffer) if sink isa type]
end
sinks(buffer::SinkBuffer, sinks::Vector{SinkBuffer}) = push!(sinks, buffer)

mutable struct SequenceMeasState <: MeasurementState
  numFrames::Int
  channel::Union{Channel, Nothing}
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  sequenceBuffer::StorageBuffer
  sensorBuffer::Union{Vector{StorageBuffer}, Nothing}
  type::AsyncMeasTyp
end

#### Scanner Measurement Functions ####
####  Async version  ####
SequenceMeasState() = SequenceMeasState(0, 1, nothing, nothing, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, nothing, RegularAsyncMeas())
