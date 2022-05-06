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
  @debug "Allocating buffer for $numFrames frames"
  # TODO implement properly with only RxMeasurementChannels
  buffer = zeros(Float32,rxNumSamplingPoints, length(rxChannels(sequence)),numPeriods,numFrames) # TODO: Change to Array{Float32, 4}(undef, rxNumSamplingPoints, length(rxChannels(sequence)),numPeriods,numFrames)?
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

  amps = getAmplifiers(scanner_)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(union(acyclicElectricalTxChannels(sequence), periodicElectricalTxChannels(sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
    @sync for amp in amps
      @async turnOn(amp)
    end
  end
  
  endFrame = nothing
  try
    daq = getDAQ(scanner_)
    endFrame = asyncProducer(channel, daq, sequence, prepTx = prepTx)
  finally
    daq = getDAQ(scanner_)
    if isnothing(endFrame)
      endSequence(daq, endFrame)
    end
    @sync for amp in amps
      @async turnOff(amp)
    end
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

  @debug "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(measState.asyncBuffer, chunk)
      updateFrameBuffer!(measState, daq)
    end
    sleep(0.001)
  end
  @debug "Consumer end"

  # TODO calibTemperatures is not filled in asyncVersion yet, would need own innerAsyncConsumer
  #if length(measState.temperatures) > 0
  #  params["calibTemperatures"] = measState.temperatures
  #end
end

