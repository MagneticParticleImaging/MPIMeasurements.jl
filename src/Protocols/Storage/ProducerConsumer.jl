SequenceMeasState(x, sequence::ControlSequence, sequenceBuffer::Nothing = nothing) = SequenceMeasState(x, sequence, StorageBuffer[])
function SequenceMeasState(x, sequence::ControlSequence, sequenceBuffer::Vector{StorageBuffer})
  numFrames = acqNumFrames(sequence.targetSequence)
  numPeriods = acqNumPeriodsPerFrame(sequence.targetSequence)
  # TODO function for length(keys(simpleChannel))
  len = length(keys(sequence.simpleChannel))
  buffer = DriveFieldBuffer(1, zeros(ComplexF64, len, len, numPeriods, numFrames), sequence)
  avgFrames = acqNumFrameAverages(sequence.targetSequence)
  if avgFrames > 1
    samples = rxNumSamplesPerPeriod(sequence.targetSequence)
    periods = acqNumPeriodsPerFrame(sequence.targetSequence)
    buffer = AverageBuffer(buffer, samples, len, periods, avgFrames)
  end
  return SequenceMeasState(x, sequence.targetSequence, push!(sequenceBuffer, buffer))
end
SequenceMeasState(protocol::Protocol, x, sequenceBuffer::Union{Nothing, Vector{StorageBuffer}} = nothing) = SequenceMeasState(getDAQ(scanner(protocol)), x, sequenceBuffer)
function SequenceMeasState(daq::RedPitayaDAQ, sequence::Sequence, sequenceBuffer::Union{Nothing, Vector{StorageBuffer}} = nothing)
  numFrames = acqNumFrames(sequence)

  # Prepare buffering structures
  @debug "Allocating buffer for $numFrames frames"
  buffer = SimpleFrameBuffer(sequence)
  if acqNumFrameAverages(sequence) > 1
    buffer = AverageBuffer(buffer, sequence)
  end
  channel = Channel{channelType(daq)}(32)
  
  buffers = StorageBuffer[buffer]
  if !isnothing(sequenceBuffer)
    push!(buffers, sequenceBuffer...)
  end

  buffer = FrameSplitterBuffer(daq, buffers)

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

asyncConsumer(measState::SequenceMeasState) = asyncConsumer(measState.channel, measState.sequenceBuffer, measState.deviceBuffers)
function asyncConsumer(channel::Channel, sequenceBuffer::StorageBuffer, deviceBuffers::Union{Vector{DeviceBuffer}, Nothing} = nothing)
  @debug "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      update = push!(sequenceBuffer, chunk)
      if !isnothing(update) && !isnothing(deviceBuffers)
        for buffer in deviceBuffers
          update!(buffer, update...)
        end
      end
    end
    sleep(0.001)
  end
  @debug "Consumer end"
end