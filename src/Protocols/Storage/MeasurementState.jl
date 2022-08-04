abstract type AsyncBuffer end
abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasType(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

mutable struct FrameAverageBuffer
  buffer::Array{Float32, 4}
  setIndex::Int
end
FrameAverageBuffer(samples, channels, periods, avgFrames) = FrameAverageBuffer(zeros(Float32, samples, channels, periods, avgFrames), 1)

mutable struct SequenceMeasState
  numFrames::Int
  nextFrame::Int
  channel::Union{Channel, Nothing}
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  asyncBuffer::AsyncBuffer
  buffer::Array{Float32,4}
  avgBuffer::Union{FrameAverageBuffer, Nothing}
  #temperatures::Matrix{Float64} temps are not implemented atm
  type::AsyncMeasTyp
end

#### Scanner Measurement Functions ####
####  Async version  ####
SequenceMeasState() = SequenceMeasState(0, 1, nothing, nothing, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, RegularAsyncMeas())