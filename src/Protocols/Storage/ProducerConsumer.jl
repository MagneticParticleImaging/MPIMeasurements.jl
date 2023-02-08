function asyncMeasurement(protocol::Protocol, sequence::Sequence)
  scanner_ = scanner(protocol)
  prepareAsyncMeasurement(protocol, sequence)
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState.channel, protocol)
  return protocol.seqMeasState
end

SequenceMeasState(x, sequence::ControlSequence) = SequenceMeasState(x, sequence.targetSequence)
SequenceMeasState(protocol::Protocol, x) = SequenceMeasState(getDAQ(scanner(protocol)), x)
function SequenceMeasState(daq::RedPitayaDAQ, sequence::Sequence)
  numFrames = acqNumFrames(sequence)

  # Prepare buffering structures
  @debug "Allocating buffer for $numFrames frames"
  buffer = SimpleFrameBuffer(sequence)
  if acqNumFrameAverages(sequence) > 1
    buffer = AverageBuffer(buffer, sequence)
  end
  channel = Channel{channelType(daq)}(32)
  buffer = FrameSplitterBuffer(daq, [buffer])

  # Prepare measState
  measState = SequenceMeasState(numFrames, channel, nothing, nothing, AsyncBuffer(buffer, daq), nothing, asyncMeasType(sequence))

  return measState
end

asyncProducer(channel, protocol, sequence::ControlSequence) = asyncProducer(channel, protocol, sequence.targetSequence)
function asyncProducer(channel::Channel, protocol::Protocol, sequence::Sequence)
  scanner_ = scanner(protocol)
  su = getSurveillanceUnit(scanner_) # Maybe also support multiple SU units?
  if !isnothing(su)
    enableACPower(su)
    # TODO Send expected enable time to SU
  end
  tempControl = getTemperatureController(scanner_)
  if !isnothing(tempControl)
    disableControl(tempControl)
  end
  robots = getRobots(scanner_)
  for robot in robots
    disable(robot)
  end

  amps = getAmplifiers(scanner_)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(vcat(acyclicElectricalTxChannels(sequence), periodicElectricalTxChannels(sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
    @sync for amp in amps
      @async turnOn(amp)
    end
  end
  
  endSample = nothing
  try
    daq = getDAQ(scanner_)
    endSample = asyncProducer(channel, daq, sequence)
  finally
    try
      daq = getDAQ(scanner_)
      if !isnothing(endSample)
        endSequence(daq, endSample)
      end
    catch ex
      @error "Could not stop tx"
      @error ex
    end 
    for amp in amps
      try
        turnOff(amp)
      catch ex
        @error "Could not turn off amplifier $(deviceID(amp))"
        @error ex
      end
    end
    try 
      if !isnothing(su)
        disableACPower(su)
      end
    catch ex
      @error "Could not disable su"
      @error ex
    end
    try 
      if !isnothing(tempControl)
        enableControl(tempControl)
      end
    catch ex
      @error "Could not enable heating control"
      @error ex
    end
    for robot in robots
      try
        enable(robot)
      catch ex
        @error "Could not turn off roboter $(deviceID(robot))"
      @error ex 
      end
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
      push!(measState.sequenceBuffer, chunk)
    end
    sleep(0.001)
  end
  @debug "Consumer end"

  # TODO calibTemperatures is not filled in asyncVersion yet, would need own innerAsyncConsumer
  #if length(measState.temperatures) > 0
  #  params["calibTemperatures"] = measState.temperatures
  #end
end