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

function asyncMeasurement(protocol::Protocol, sequence::Sequence)
  scanner_ = scanner(protocol)
  prepareAsyncMeasurement(protocol, sequence)
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState.channel, protocol)
  return protocol.seqMeasState
end

function prepareAsyncMeasurement(protocol::Protocol, sequence::Sequence)
  scanner_ = scanner(protocol)
  daq = getDAQ(scanner_)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  frameAverage = acqNumFrameAverages(sequence)
  setup(daq, sequence)

  # Prepare buffering structures
  @info "Allocating buffer for $numFrames frames"
  # TODO implement properly with only RxMeasurementChannels
  buffer = zeros(Float32,rxNumSamplingPoints, length(rxChannels(sequence)),numPeriods,numFrames)
  #buffer = zeros(Float32,rxNumSamplingPoints,numRxChannelsMeasurement(daq),numPeriods,numFrames)
  avgBuffer = nothing
  if frameAverage > 1
    avgBuffer = FrameAverageBuffer(zeros(Float32, frameAverageBufferSize(daq, frameAverage)), 1)
  end
  channel = Channel{channelType(daq)}(32)

  # Prepare measState
  measState = SequenceMeasState(numFrames, 1, nothing, nothing, nothing, AsyncBuffer(daq), buffer, avgBuffer, asyncMeasType(sequence))
  measState.channel = channel

  protocol.seqMeasState = measState
end

function asyncProducer(channel::Channel, protocol::Protocol, sequence::Sequence; prepTx = true)
  scanner_ = scanner(protocol)
  su = getSurveillanceUnit(scanner_) # Maybe also support multiple SU units?
  if !isnothing(su)
    enableACPower(su)
    # TODO Send expected enable time to SU
  end
  robots = getRobots(scanner_)
  for robot in robots
    disable(robot)
  end

  try
    daq = getDAQ(scanner_)
    asyncProducer(channel, daq, sequence, prepTx = prepTx)
  finally
    if !isnothing(su)
      disableACPower(su)
    end
    for robot in robots
      enable(robot)
    end
  end
end

# Default Consumer
function asyncConsumer(channel::Channel, protocol::Protocol)
  scanner_ = scanner(protocol)
  daq = getDAQ(scanner_)
  measState = protocol.seqMeasState

  @info "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(measState.asyncBuffer, chunk)
      updateFrameBuffer!(measState, daq)
    end
    sleep(0.001)
  end
  @info "Consumer end"

  # TODO calibTemperatures is not filled in asyncVersion yet, would need own innerAsyncConsumer
  #if length(measState.temperatures) > 0
  #  params["calibTemperatures"] = measState.temperatures
  #end
end