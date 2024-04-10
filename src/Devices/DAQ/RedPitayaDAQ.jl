export RampingMode, NONE, HOLD, STARTUP
@enum RampingMode NONE HOLD STARTUP

export RedPitayaDAQParams
Base.@kwdef mutable struct RedPitayaDAQParams <: DAQParams
  "All configured channels of this DAQ device."
  channels::Dict{String, DAQChannelParams}
  "IPs of the Red Pitayas"
  ips::Vector{String}
  "Trigger mode of the Red Pitayas. Default: `ALL_INTERNAL`."
  triggerMode::RedPitayaDAQServer.ClusterTriggerSetup = ALL_INTERNAL
  "Time to wait after a reset has been issued."
  resetWaittime::typeof(1.0u"s") = 45u"s"
  rampingMode::RampingMode = HOLD
  rampingFraction::Float32 = 1.0
  "Flag for using the counter trigger"
  useCounterTrigger::Bool = false
  "Source type of the counter trigger"
  counterTriggerSourceType::CounterTriggerSourceType =  COUNTER_TRIGGER_DIO
  "DIO pin used for the counter trigger"
  counterTriggerSourceChannel::DIOPins = DIO7_P
end

Base.@kwdef struct RedPitayaLUTChannelParams <: TxChannelParams
  channelIdx::Int64
  calibration::Union{typeof(1.0u"V/T"), typeof(1.0u"V/A"), Nothing} = nothing
end

function createDAQChannel(::Type{RedPitayaLUTChannelParams}, dict::Dict{String, Any})
  calib = nothing
  if haskey(dict, "calibration")
    calib = uparse.(dict["calibration"])

    if unit(upreferred(calib)) == upreferred(u"V/T")
      calib = calib .|> u"V/T"
    elseif unit(upreferred(calib)) == upreferred(u"V/A")
      calib = calib .|> u"V/A"
    else
      error("The values have to be either given as a V/T or in V/A. You supplied the type `$(eltype(calib))`.")
    end
  end
  return RedPitayaLUTChannelParams(channelIdx=dict["channel"], calibration = calib)
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function RedPitayaDAQParams(dict::Dict{String, Any})
  return createDAQParams(RedPitayaDAQParams, dict)
end

export RedPitayaDAQ
Base.@kwdef mutable struct RedPitayaDAQ <: AbstractDAQ
  @add_device_fields RedPitayaDAQParams

  "Reference to the Red Pitaya cluster"
  rpc::Union{RedPitayaCluster, Nothing} = nothing
  rpv::Union{RedPitayaClusterView, Nothing} = nothing

  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []
  # Sequence and Ramping
  acqSeq::Union{Vector{AbstractSequence}, Nothing} = nothing
  rampingChannel::Set{Int64} = Set()
  samplesPerStep::Int32 = 0
  decimation::Int32 = 64
  samplingPoints::Int = 1
  sampleAverages::Int = 1
  acqPeriodsPerPatch::Int = 1
  acqNumFrames::Int = 1
  acqNumFrameAverages::Int = 1
  acqNumAverages::Int = 1

  "Reference counter for the counter trigger"
  referenceCounter::Integer = 0
  "Samples prior to acquisition for the counter trigger"
  presamples::Integer = 0
end

function _init(daq::RedPitayaDAQ)
  # force all calibration transfer functions to be read from disk
  for channelID in keys(daq.params.channels)
    if isa(channel(daq, channelID), DAQTxChannelParams)
      calibration(daq, channelID)
      feedbackCalibration(daq, channelID)
    end
  end

  # Restart the DAQ if necessary
  try
    daq.rpc = RedPitayaCluster(daq.params.ips, triggerMode = daq.params.triggerMode)
  catch e
    if hasDependency(daq, SurveillanceUnit)
      su = dependency(daq, SurveillanceUnit)
      if hasResetDAQ(su)
        @info "Connection to DAQ could not be established! Restart (wait $(daq.resetWaittime) seconds...)!"
        resetDAQ(su)
        sleep(daq.resetWaittime)
        daq.rpc = RedPitayaCluster(daq.params.ips)
      else
        rethrow()
      end
    else
      @error "Error with Red Pitaya occured and the DAQ does not have access to a surveillance "*
             "unit for resetting it. Please check closely if this should be the case."
      rethrow()
    end
  end

  if serverMode(daq.rpc) == ACQUISITION
    masterTrigger!(daq.rpc, false)
    serverMode!(daq.rpc, CONFIGURATION)
  end

  if usesCounterTrigger(daq)
    counterTrigger_reset!(daq.rpc)
    counterTrigger_sourceType!(daq.rpc, daq.params.counterTriggerSourceType)
    counterTrigger_sourceChannel!(daq.rpc, daq.params.counterTriggerSourceChannel)
    DIODirection!(master(daq.rpc), daq.params.counterTriggerSourceChannel, DIO_IN)
    counterTrigger_enabled!(daq.rpc, true)
  end

  daq.present = true
end

neededDependencies(::RedPitayaDAQ) = []
optionalDependencies(::RedPitayaDAQ) = [TxDAQController, SurveillanceUnit]

Base.close(daq::RedPitayaDAQ) = daq.rpc

export usesCounterTrigger
usesCounterTrigger(daq::RedPitayaDAQ) = daq.params.useCounterTrigger

export referenceCounter
referenceCounter(daq::RedPitayaDAQ) = daq.referenceCounter

export referenceCounter!
referenceCounter!(daq::RedPitayaDAQ, referenceCounter) = daq.referenceCounter = referenceCounter

export presamples
presamples(daq::RedPitayaDAQ) = daq.presamples

export presamples!
presamples!(daq::RedPitayaDAQ, presamples) = daq.presamples = presamples

export counterTrigger_lastCounter
counterTrigger_lastCounter(daq::RedPitayaDAQ) = RedPitayaDAQServer.counterTrigger_lastCounter(daq.rpc)

#### Sequence ####
function setSequenceParams(daq::RedPitayaDAQ, sequence::Sequence)
  setRampingParams(daq, sequence)
  daq.acqPeriodsPerPatch = acqNumPeriodsPerPatch(sequence)
  acyclic = acyclicElectricalTxChannels(sequence)
  if length(acyclic) > 0
    setAcyclicParams(daq, acyclic)
  else
    setPeriodicParams(daq)
  end
end

function setRampingParams(daq::RedPitayaDAQ, sequence::Sequence)
  daq.rampingChannel = Set()
  # Create mapping from field to channel
  txChannels = [channel for channel in daq.params.channels if channel[2] isa TxChannelParams]
  idxMap = Dict{String, Union{Int64, Nothing}}()
  for channel in txChannels
    m = nothing
    idx = channel[2].channelIdx
    if channel[2] isa DAQTxChannelParams
      m = idx
    elseif channel[2] isa RedPitayaLUTChannelParams
      # Map to fast DAC
      if (idx -1) % 6 < 2
        m = Int64(idx - (ceil(idx/6) - 1) * 4)
      end
    end
    idxMap[channel[1]] = m
  end

  # Get max ramp time for each channel
  rampMap = Dict{Int64, Float64}()
  for field in fields(sequence)
    rampUp = ustrip(u"s", safeStartInterval(field))
    rampDown = ustrip(u"s", safeEndInterval(field))
    if rampUp != rampDown
      throw(ScannerConfigurationError("Field $(id(field)) has different ramp-up and ramp-down intervals which is not supported."))
    end
    if rampUp != 0.0
      for channel in electricalTxChannels(field)
        if !haskey(idxMap, id(channel))
          throw(ScannerConfigurationError("No tx channel defined for field channel $(id(channel))"))
        end
        idx = idxMap[id(channel)]
        if !isnothing(idx)
          rampMap[idx] = max(get(rampMap, idx, 0.0), rampUp)
        end
      end
    end
  end

  # Set ramp time per channel
  execute!(daq.rpc) do batch
    for (idx, val) in rampMap
      @add_batch batch rampingDAC!(daq.rpc, idx, val)
      @add_batch batch enableRamping!(daq.rpc, idx, true)
      push!(daq.rampingChannel, idx)
    end
  end
end

function setPeriodicParams(daq)
  # Atm sequences with no acyclic params have 1 period per patch -> periodsPerFrame patches
  # Alternative solution could be 1 patch per frame, but then measurements would again be multiples of frames
  # Or divide the frame in a number of patches based on the ramping time
  luts = Array{Union{Nothing, Array{Float64}}}(nothing, length(daq.rpc))
  enableLuts = Array{Union{Nothing, Array{Bool}}}(nothing, length(daq.rpc))
  for i = 1:length(daq.rpc)
    luts[i] = createEmptyLUT(periodsPerFrame(daq.rpc))
    enableLuts[i] = createEmptyEnable(periodsPerFrame(daq.rpc))
  end
  setSequenceParams(daq, luts, enableLuts)
end

function setAcyclicParams(daq, seqChannels::Vector{AcyclicElectricalTxChannel})
  luts = Array{Union{Nothing, Array{Float64}}}(nothing, length(daq.rpc))
  enableLuts = Array{Union{Nothing, Array{Bool}}}(nothing, length(daq.rpc))

  # Pair LUT/txSlow Channel with acyclic seq channel
  lutChannels = [channel for channel in daq.params.channels if channel[2] isa RedPitayaLUTChannelParams]
  channelMapping = []
  for channel in seqChannels
    index = findfirst(x-> id(channel) == x[1], lutChannels)
    if !isnothing(index)
      push!(channelMapping, (lutChannels[index][2], channel))
    else
      throw(ScannerConfigurationError("No txSlow Channel defined for Field channel $(id(channel))"))
    end
  end

  # Prepare base value & enable arrays
  emptyLUT = createEmptyLUT(seqChannels)
  emptyEnable = createEmptyEnable(seqChannels)
  # Insert each RP value & enable "values" into the respective arrays
  for rp in 1:length(daq.rpc)
    rpLut = copy(emptyLUT)
    rpEnable = copy(emptyEnable)
    start = (rp - 1) * 6 + 1
    currentPossibleChannels = collect(start:start+5)
    currentMapping = [(lut, seq) for (lut, seq) in channelMapping if lut.channelIdx in currentPossibleChannels]
    if !isempty(currentMapping)
      createLUT!(rpLut, start, currentMapping)
      createEnableLUT!(rpEnable, start, currentMapping)
    end
    luts[rp] = rpLut
    enableLuts[rp] = rpEnable
  end
  setSequenceParams(daq, luts, enableLuts)
end

function setSequenceParams(daq::RedPitayaDAQ, luts::Vector{Union{Nothing, Array{Float64}}}, enableLuts::Vector{Union{Nothing, Array{Bool}}})
  if length(luts) != length(daq.rpc)
    throw(DimensionMismatch("$(length(luts)) LUTs do not match $(length(daq.rpc)) RedPitayas"))
  end
  if length(enableLuts) != length(daq.rpc)
    throw(DimensionMismatch("$(length(enableLuts)) enableLUTs do not match $(length(daq.rpc)) RedPitayas"))
  end
  # Restrict to sequences of equal length, not a requirement of RedPitayaDAQServer, but of MPIMeasurements for simplicity
  sizes = map(x-> size(x, 2) , filter(!isnothing, luts))
  if !isempty(sizes)
    if minimum(sizes) != maximum(sizes)
      throw(DimensionMismatch("LUTs do not have equal amount of steps"))
    end
  else
    @debug "There are no LUTs to set."
  end

  @info "Set sequence params"

  stepsPerRepetition = div(periodsPerFrame(daq.rpc), daq.acqPeriodsPerPatch)
  @debug "Set sequence params" samplesPerStep=div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition)
  result = execute!(daq.rpc) do batch
    @add_batch batch samplesPerStep!(daq.rpc, div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition))
    @add_batch batch clearSequence!(daq.rpc)
    @add_batch batch samplesPerStep(daq.rpc)
  end
  daq.samplesPerStep = result[3][1]

  rampingSteps = 0
  fractionSteps = 0
  if !isempty(daq.rampingChannel)
    result = execute!(daq.rpc) do batch
      for i in daq.rampingChannel
        @add_batch batch rampingDAC(daq.rpc, i)
      end
    end
    rampTime = maximum([maximum(filter(!isnothing, x)) for x in result])
    samplingRate = 125e6/daq.decimation
    timePerStep = daq.samplesPerStep/samplingRate
    rampingSteps = Int64(ceil(rampTime/timePerStep))
    fractionSteps = Int64(ceil(daq.params.rampingFraction * sizes[1]))
  end

  acqSeq = Array{AbstractSequence}(undef, length(daq.rpc))
  @sync for (i, rp) in enumerate(daq.rpc)
    @async begin
      lut = luts[i]
      enable = enableLuts[i]
      if !isnothing(lut)
        seqChan!(rp, size(lut, 1))
        rpSeq = rpSequence(daq.rpc[i], lut, enable, daq.acqNumFrames*daq.acqNumFrameAverages, daq.params.rampingMode, rampingSteps, fractionSteps)
        acqSeq[i] = rpSeq
        sequence!(rp, rpSeq)
      else
        # TODO What to do in this case, see maybe fill with zeros in other setSequenceParams
      end
    end
  end
  daq.acqSeq = isempty(acqSeq) ? nothing : acqSeq
end

function rpSequence(rp::RedPitaya, lut::Array{Float64}, enable::Union{Nothing, Array{Bool}}, repetitions::Integer, mode::RampingMode, rampingSteps, fractionSteps)
  seq = nothing
  if mode == NONE
    seq = RedPitayaDAQServer.ConstantRampingSequence(lut, repetitions, Float32(0.0), rampingSteps, enable)
  elseif mode == HOLD
    seq = RedPitayaDAQServer.HoldBorderRampingSequence(lut, repetitions, rampingSteps + fractionSteps, enable)
  elseif mode == STARTUP
    seq = RedPitayaDAQServer.StartUpSequence(lut, repetitions, rampingSteps + fractionSteps, fractionSteps, enable)
  else
    ScannerConfigurationError("Ramping mode $mode is not yet implemented.")
  end
  return seq
end

function createEmptyLUT(numValues::Integer)
  return zeros(Float32, 6, numValues)
end

function createEmptyLUT(seqChannels::Vector{AcyclicElectricalTxChannel})
  # Assumption: size of all lutValues is equal, checked during sending to RP
  # RedPitaya server bug for more than two channel atm
  return createEmptyLUT(size(values(seqChannels[1]), 1))
end

function createLUT!(lut::Array{Float32}, start, channelMapping)
  channelMapping = sort(channelMapping, by = x -> x[1].channelIdx)
  lutValues = []
  lutIdx = []
  for (lutChannel, seqChannel) in channelMapping
    push!(lutValues, ustrip.(u"V", values(seqChannel)))
    push!(lutIdx, lutChannel.channelIdx)
  end

  # Idx from 1 to 6
  lutIdx = (lutIdx.-start).+1
  # Fill skipped channels with 0.0, assumption: size of all lutValues is equal
  #lut = zeros(Float32, maximum(lutIdx), size(lutValues[1], 1))
  for (i, lutIndex) in enumerate(lutIdx)
    lut[lutIndex, :] = lutValues[i]
  end
  return lut
end

function createEmptyEnable(numValues::Integer)
  return ones(Bool, 6, numValues)
end

function createEmptyEnable(seqChannels::Vector{AcyclicElectricalTxChannel})
    # Assumption: size of all enableValues is equal, checked during sending to RP
    return createEmptyEnable(size(values(seqChannels[1]), 1))
end

function createEnableLUT!(enableLut::Array{Bool}, start, channelMapping)
  channelMapping = sort(channelMapping, by = x -> x[1].channelIdx)
  enableLutValues = []
  enableLutIdx = []
  for (lutChannel, seqChannel) in channelMapping
    tempValues = enableValues(seqChannel)
    push!(enableLutValues, tempValues)
    push!(enableLutIdx, lutChannel.channelIdx)
  end

  # Idx from 1 to 6
  enableLutIdx = (enableLutIdx .- start) .+ 1
  # Fill skipped channels with true, assumption: size of all enableLutValues is equal
  #enableLut = ones(Bool, maximum(enableLutIdx), size(enableLutValues[1], 1))
  for (i, enableLutIndex) in enumerate(enableLutIdx)
    enableLut[enableLutIndex, :] = enableLutValues[i]
  end
  return enableLut
end

function endSequence(daq::RedPitayaDAQ, endSample)
  wp = currentWP(daq.rpc)
  # Wait for sequence to finish
  while wp < endSample
    wp = currentWP(daq.rpc)
  end
  stopTx(daq)
end

function getTiming(daq::RedPitayaDAQ)
  # TODO How to signal end of sequences without any LUTs
  timing = seqTiming(daq.acqSeq[1])
  sampleTiming = (start=timing.start * daq.samplesPerStep, down=timing.down * daq.samplesPerStep, finish=timing.finish * daq.samplesPerStep)
  return sampleTiming
end

#### Producer/Consumer ####
mutable struct RedPitayaAsyncBuffer <: AsyncBuffer
  samples::Union{Matrix{Int16}, Nothing}
  performance::Vector{Vector{PerformanceData}}
  target::StorageBuffer
  daq::RedPitayaDAQ
end
AsyncBuffer(buffer::StorageBuffer, daq::RedPitayaDAQ) = RedPitayaAsyncBuffer(nothing, Vector{Vector{PerformanceData}}(undef, 1), buffer, daq)

channelType(daq::RedPitayaDAQ) = SampleChunk

function push!(buffer::RedPitayaAsyncBuffer, chunk)
  samples = chunk.samples
  perfs = chunk.performance
  push!(buffer.performance, perfs)
  if !isnothing(buffer.samples)
    buffer.samples = hcat(buffer.samples, samples)
  else
    buffer.samples = samples
  end
  for (i, p) in enumerate(perfs)
    if p.status.overwritten || p.status.corrupted
        @warn "RedPitaya $i lost data"
    end
    if p.status.stepsLost
      @warn "RedPitaya $i lost sequence steps"
    end
  end
  frames = convertSamplesToFrames!(buffer)
  if !isnothing(frames)
    return push!(buffer.target, frames)
  else
    return nothing
  end
end
sinks!(buffer::RedPitayaAsyncBuffer, sinks::Vector{SinkBuffer}) = sinks!(buffer.target, sinks)

function frameAverageBufferSize(daq::RedPitayaDAQ, frameAverages)
  return samplesPerPeriod(daq.rpc), length(daq.rxChanIDs), periodsPerFrame(daq.rpc), frameAverages
end

function startProducer(channel::Channel, daq::RedPitayaDAQ, numFrames; isControlStep=false)
  # TODO How to signal end of sequences without any LUTs
  timing = nothing
  if !isnothing(daq.acqSeq)
    timing = getTiming(daq)
  end
  startTx(daq, isControlStep=isControlStep)

  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  startSample = timing.start
  samplesToRead = samplesPerFrame * numFrames
  chunkSize = Int(ceil(0.1 * (125e6/daq.decimation)))

  rpu = daq.rpc
  if !isnothing(daq.rpv)
    rpu = daq.rpv
  end

  # Start pipeline
  @debug "Pipeline started"
  try
    @debug "Producer:" currentWP(daq.rpc)
    readSamples(rpu, startSample, samplesToRead, channel, chunkSize = chunkSize)
  catch e
    @info "Attempting reconnect to reset pipeline"
    daq.rpc = RedPitayaCluster(daq.params.ips; triggerMode=daq.params.triggerMode)
    if serverMode(daq.rpc) == ACQUISITION
      for ch in daq.rampingChannel
        enableRampDown!(daq.rpc, ch, true)
      end
      # TODO wait
      masterTrigger!(daq.rpc, false)
      serverMode!(daq.rpc, CONFIGURATION)
    end
    daq.rpv = nothing
    rethrow(e)
  end
  @debug "Pipeline finished"
  return timing.finish
end


function convertSamplesToFrames!(buffer::RedPitayaAsyncBuffer)
  daq = buffer.daq
  unusedSamples = buffer.samples
  samples = buffer.samples
  frames = nothing
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  samplesInBuffer = size(samples)[2]
  framesInBuffer = div(samplesInBuffer, samplesPerFrame)

  if framesInBuffer > 0
      samplesToConvert = view(samples, :, 1:(samplesPerFrame * framesInBuffer))
      chan = numChan(daq.rpc)
      rpu = daq.rpc
      if !isnothing(daq.rpv)
        rpu = daq.rpv
        chan = numChan(daq.rpv)
      end
      frames = convertSamplesToFrames(rpu, samplesToConvert, chan, samplesPerPeriod(daq.rpc), periodsPerFrame(daq.rpc), framesInBuffer, daq.acqNumAverages, 1)
      if (samplesPerFrame * framesInBuffer) + 1 <= samplesInBuffer
          unusedSamples = samples[:, (samplesPerFrame * framesInBuffer) + 1:samplesInBuffer]
      else
        unusedSamples = nothing
      end
  end

  buffer.samples = unusedSamples
  return frames
end

function retrieveMeasAndRef!(frames::Array{Float32, 4}, daq::RedPitayaDAQ)
  rxIds = channelIdx(daq, daq.rxChanIDs)
  refIds = channelIdx(daq, daq.refChanIDs)
  # Map channel index to their respective index in the view
  if !isnothing(daq.rpv)
    rxIds = map(x->clusterToView(daq.rpv, x), rxIds)
    refIds = map(x->clusterToView(daq.rpv, x), refIds)
  end
  uMeas = frames[:,rxIds,:,:]
  uRef = frames[:, refIds,:,:]
  return uMeas, uRef
end

#### Tx and Rx
function setup(daq::RedPitayaDAQ, sequence::Sequence)
  stopTx(daq)
  setupRx(daq, sequence)
  sequenceVolt = applyForwardCalibration(sequence, daq)
  setupTx(daq, sequenceVolt)
  prepareTx(daq, sequenceVolt)
  setSequenceParams(daq, sequenceVolt)
end

function setupTx(daq::RedPitayaDAQ, sequence::Sequence)
  @debug "Setup tx"
  
  periodicChannels = periodicElectricalTxChannels(sequence)

  if any([length(component.amplitude) > 1 for channel in periodicChannels for component in periodicElectricalComponents(channel)])
    error("The Red Pitaya DAQ cannot work with more than one period in a frame or frequency sweeps yet.")
  end
    
  @debug "SetupTx: Outputting the following offsets" offsets=[offset(chan) for chan in periodicChannels]

  # Iterate over sequence(!) channels
  execute!(daq.rpc) do batch
    baseFreq = txBaseFrequency(sequence)
    for channel in periodicChannels
      setupTxChannel!(batch, daq, channel, baseFreq)
    end
  end
end
function setupTxChannel(daq::RedPitayaDAQ, channel::PeriodicElectricalChannel, baseFreq)
  execute!(daq.rpc) do batch
    setupTxChannel!(batch, daq, channel, baseFreq)
  end
end
function setupTxChannel!(batch::ScpiBatch, daq::RedPitayaDAQ, channel::PeriodicElectricalChannel, baseFreq)
  channelIdx_ = channelIdx(daq, id(channel)) # Get index from scanner(!) channel
  @add_batch batch offsetDAC!(daq.rpc, channelIdx_, ustrip(u"V", offset(channel)))

  for (idx, component) in enumerate(periodicElectricalComponents(channel)) # in the future add the SweepElectricalComponents as well
    setupTxComponent!(batch, daq, channel, component, idx, baseFreq)
  end
  
  awgComps = arbitraryElectricalComponents(channel) 
  if length(awgComps) > 1
    throw(SequenceConfigurationError("The channel with the ID $(id(channel)) defines more than one arbitrary electrical component, which is not supported."))
  elseif length(awgComps) == 1
    setupTxComponent!(batch, daq, channel, awgComps[1], 0, baseFreq)
  end

end

function setupTxComponent(daq::RedPitayaDAQ, channel::PeriodicElectricalChannel, component, componentIdx, baseFreq)
  execute!(daq.rpc) do batch
    setupTxComponent!(batch, daq, channel, component, componentIdx, baseFreq)
  end
end
function setupTxComponent!(batch::ScpiBatch, daq::RedPitayaDAQ, channel::PeriodicElectricalChannel, component::Union{PeriodicElectricalComponent, SweepElectricalComponent}, componentIdx, baseFreq)
  if componentIdx > 3
    throw(SequenceConfigurationError("The channel with the ID `$(id(channel))` defines more than three fixed waveform components, this is more than what the RedPitaya offers. Use an arbitrary waveform if a fourth is necessary."))
  end
  channelIdx_ = channelIdx(daq, id(channel)) # Get index from scanner(!) channel
  freq = ustrip(u"Hz", baseFreq) / divider(component)
  @add_batch batch frequencyDAC!(daq.rpc, channelIdx_, componentIdx, freq)
  waveform_ = uppercase(fromWaveform(waveform(component)))
  if !isWaveformAllowed(daq, id(channel), waveform(component))
    throw(SequenceConfigurationError("The channel with the ID `$(id(channel))` "*
                                   "defines a waveform of $waveform_, but the scanner channel does not allow this."))
  end
  @add_batch batch signalTypeDAC!(daq.rpc, channelIdx_, componentIdx, waveform_)
end
function setupTxComponent!(batch::ScpiBatch, daq::RedPitayaDAQ, channel::PeriodicElectricalChannel, component::ArbitraryElectricalComponent, componentIdx, baseFreq)
  channelIdx_ = channelIdx(daq, id(channel)) # Get index from scanner(!) channel
  freq = ustrip(u"Hz", baseFreq) / divider(component)
  # AWG is always fourth component
  @add_batch batch frequencyDAC!(daq.rpc, channelIdx_, 4, freq)
  waveform_ = uppercase(fromWaveform(waveform(component)))
  if !isWaveformAllowed(daq, id(channel), waveform(component))
    throw(SequenceConfigurationError("The channel with the ID `$(id(channel))` "*
                                   "defines a waveform of $waveform_, but the scanner channel does not allow this."))
  end
  # Waveform is set together with amplitudes for arbitrary waveforms
end

function setupRx(daq::RedPitayaDAQ, decimation, samplesPerPeriod, periodsPerFrame)
  @debug "Setup rx"
  decimation!(daq.rpc, decimation) # Only command with network communication here
  samplesPerPeriod!(daq.rpc, samplesPerPeriod)
  periodsPerFrame!(daq.rpc, periodsPerFrame)
  #numSlowADCChan(daq.rpc, 4) # Not used as far as I know
end
function setupRx(daq::RedPitayaDAQ, sequence::Sequence)
  @assert txBaseFrequency(sequence) == 125.0u"MHz" "The base frequency is fixed for the Red Pitaya "*
  "and must thus be 125 MHz and not $(txBaseFrequency(sequence))."

  # The decimation has to be divisible by 2 and must be 8 or larger
  decimation_ = upreferred(txBaseFrequency(sequence)/rxSamplingRate(sequence))
  if iseven(decimation_) &&  decimation_ >= 8
    daq.decimation = decimation_
  else
    throw(ScannerConfigurationError("The decimation derived from the rx bandwidth of $(rxBandwidth(sequence)) and "*
      "the base frequency of $(txBaseFrequency(sequence)) has a value of $decimation_ "*
      "but has to be a power of 2"))
  end

  daq.acqNumFrames = acqNumFrames(sequence)
  daq.acqNumFrameAverages = acqNumFrameAverages(sequence)
  daq.acqNumAverages = acqNumAverages(sequence)

  daq.rxChanIDs = []
  for channel in rxChannels(sequence)
    push!(daq.rxChanIDs, id(channel))
  end

  # TODO possibly move some of this into abstract daq
  daq.refChanIDs = []
  txChannels = [channel[2] for channel in daq.params.channels if channel[2] isa DAQTxChannelParams]
  daq.refChanIDs = unique([tx.feedback.channelID for tx in txChannels if !isnothing(tx.feedback)])

  # Construct view to save bandwidth
  rxIDs = sort(union(channelIdx(daq, daq.rxChanIDs), channelIdx(daq, daq.refChanIDs)))
  selection = [false for i = 1:length(daq.rpc)]
  for i in map(x->div(x -1, 2) + 1, rxIDs)
    @debug "setupRx: Adding RP id $i to cluster view"
    selection[i] = true
  end
  daq.rpv = RedPitayaClusterView(daq.rpc, selection)

  setupRx(daq, daq.decimation, rxNumSamplesPerPeriod(sequence) * daq.acqNumAverages, acqNumPeriodsPerFrame(sequence))
end
function setupRx(daq::RedPitayaDAQ, decimation, numSamplesPerPeriod, numPeriodsPerFrame, numFrames; numFrameAverage=1, numAverages=1)
  daq.decimation = decimation
  daq.acqNumFrames = numFrames
  daq.acqNumFrameAverages = numFrameAverage
  daq.acqNumAverages = numAverages
  daq.rpv = nothing
  setupRx(daq, decimation, numSamplesPerPeriod * daq.acqNumAverages, numPeriodsPerFrame)
end

# Starts both tx and rx in the case of the Red Pitaya since both are entangled by the master trigger.
function startTx(daq::RedPitayaDAQ; isControlStep=false)
  if usesCounterTrigger(daq) && !isControlStep
    counterTrigger_enabled!(daq.rpc, true)
    counterTrigger_referenceCounter!(daq.rpc, daq.referenceCounter)
    counterTrigger_presamples!(daq.rpc, daq.presamples)
  else
    counterTrigger_enabled!(daq.rpc, false)
  end

  serverMode!(daq.rpc, ACQUISITION)
  masterTrigger!(daq.rpc, true)

  if usesCounterTrigger(daq) && !isControlStep
    @info "Arming trigger"
    counterTrigger_arm!(daq.rpc)
  end

  @debug "Started tx"
end

function stopTx(daq::RedPitayaDAQ)
  masterTrigger!(daq.rpc, false)
  execute!(daq.rpc) do batch
    @add_batch batch serverMode!(daq.rpc, CONFIGURATION)
    for channel in 1:2*length(daq.rpc)
      @add_batch batch enableRamping!(daq.rpc, channel, false)
    end
  end
  clearTx!(daq)

  # We just always make sure to disable the counter trigger
  counterTrigger_enabled!(daq.rpc, false)

  @debug "Stopped tx"
end

function clearTx!(daq::RedPitayaDAQ)
  execute!(daq.rpc) do batch
    for channel = 1:2*length(daq.rpc)
      for comp = 1:4
        @add_batch batch amplitudeDAC!(daq.rpc, channel, comp, 0.0)
      end
    end
  end
end

function prepareControl(daq::RedPitayaDAQ, seq::Sequence)
  clearSequence!(daq.rpc)
  setRampingParams(daq, seq)
end

function prepareTx(daq::RedPitayaDAQ, sequence::Sequence)
  stopTx(daq)
  allAmps  = Dict{String, Vector{typeof(1.0u"V")}}()
  allPhases = Dict{String, Vector{typeof(1.0u"rad")}}()
  allAwg = Dict{String, Vector{typeof(1.0u"V")}}()
    for channel in periodicElectricalTxChannels(sequence)
    name = id(channel)
    # This should set all unused components to zero, but what about unused channels?
    amps = zeros(typeof(1.0u"V"), 3)
    phases = zeros(typeof(1.0u"rad"), 3)
    wave = zeros(typeof(1.0u"V"), 2^14)
    for (i,comp) in enumerate(periodicElectricalComponents(channel))
      # Length check < 3 happens in setupTx already
      amps[i] = amplitude(comp)
      phases[i] = phase(comp)
    end
    # Length check < 1 happens in setupTx already
    comps = arbitraryElectricalComponents(channel)
    if length(comps)==1
      wave = scaledValues(comps[1])
    end

    allAwg[name] = wave
    allAmps[name] = amps
    allPhases[name] = phases
  end
  @debug "prepareTx: Outputting the following amplitudes and phases:" allAmps allPhases awg=lineplot(1:2^14,ustrip.(u"V",hcat(collect(Base.values(allAwg))...)),ylabel="AWG / V", name=collect(Base.keys(allAwg)), canvas=DotCanvas, border=:ascii, height=10, xlim=(1,2^14))

  setTxParams(daq, allAmps, allPhases, allAwg)
end

"""
Set the amplitude and phase for all the selected channels.

Note: `amplitudes` and `phases` are defined as a dictionary of
vectors, since every channel referenced by the dict's key could
have a different amount of components.
"""
function setTxParams(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{Union{Float32, Nothing}}}, phases::Dict{String, Vector{Union{Float32, Nothing}}}, awg::Union{Dict{String, Vector{Float32}}, Nothing} = nothing)
  setTxParamsAmplitudes(daq, amplitudes)
  setTxParamsPhases(daq, phases)
  setTxParamsArbitrary(daq, awg)
end
function setTxParamsAmplitudes(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{Union{Float32, Nothing}}})
  # Determine the worst case voltage per channel
  # Note: this would actually need a fourier synthesis with the given signal type,
  # but I don't think this is necessary
  for (channelID, components_) in amplitudes
    channelVoltage = 0
    for amplitude_ in components_
      if !isnothing(amplitude_)
        channelVoltage += amplitude_
      end
    end

    if channelVoltage >= ustrip(u"V", limitPeak(daq, channelID))
      error("This should never happen!!! \nTx voltage on channel with ID `$channelID` is above the limit with a voltage of $channelVoltage.")
    end
  end

  execute!(daq.rpc) do batch
    for (channelID, components_) in amplitudes
      for (componentIdx, amplitude_) in enumerate(components_)
        if !isnothing(amplitude_)
          @add_batch batch amplitudeDAC!(daq.rpc, channelIdx(daq, channelID), componentIdx, amplitude_)
        end
      end
    end
  end
end
function setTxParamsPhases(daq::RedPitayaDAQ, phases::Dict{String, Vector{Union{Float32, Nothing}}})
  execute!(daq.rpc) do batch
    for (channelID, components_) in phases
      for (componentIdx, phase_) in enumerate(components_)
        if !isnothing(phase_)
          @add_batch batch phaseDAC!(daq.rpc, channelIdx(daq, channelID), componentIdx, phase_)
        end
      end
    end
  end
end
function setTxParamsFrequencies(daq::RedPitayaDAQ, freqs::Dict{String, Vector{Union{Float32, Nothing}}})
  execute!(daq.rpc) do batch
    for (channelID, components_) in freqs
      for (componentIdx, freq_) in enumerate(components_)
        if !isnothing(freq_)
          @add_batch batch frequencyDAC!(daq.rpc, channelIdx(daq, channelID), componentIdx, freq_)
        end
      end
    end
  end
end
function setTxParamsArbitrary(daq::RedPitayaDAQ, awgs::Dict{String, Vector{Float32}})
  for (channelID, wave) in awgs
    waveformDAC!(daq.rpc, channelIdx(daq, channelID), wave)
  end
end
function setTxParamsArbitrary(daq::RedPitayaDAQ, awg::Nothing)
  # NOP
end

function setTxParams(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{typeof(1.0u"V")}}, phases::Dict{String, Vector{typeof(1.0u"rad")}}, awg::Union{Dict{String, Vector{typeof(1.0u"V")}}, Nothing} = nothing; convolute=true)
  amplitudesFloat = Dict{String, Vector{Union{Float32, Nothing}}}()
  phasesFloat = Dict{String, Vector{Union{Float32, Nothing}}}()
  awgFloat = nothing
  for (id, amps) in amplitudes
    amplitudesFloat[id] = map(x-> isnothing(x) ? nothing : ustrip(u"V", x), amps)
  end
  for (id, phs) in phases
    phasesFloat[id] =  map(x-> isnothing(x) ? nothing : ustrip(u"rad", x), phs)
  end
  if !isnothing(awg)
    awgFloat = Dict{String, Vector{Float32}}()
    for (id, wave) in awg
      awgFloat[id] = map(x-> ustrip(u"V", x), wave)
    end
  end
  setTxParams(daq, amplitudesFloat, phasesFloat, awgFloat)
end

currentFrame(daq::RedPitayaDAQ) = RedPitayaDAQServer.currentFrame(daq.rpc)
currentPeriod(daq::RedPitayaDAQ) = RedPitayaDAQServer.currentPeriod(daq.rpc)

function readData(daq::RedPitayaDAQ, startFrame::Integer, numFrames::Integer, numBlockAverages::Integer=1)
  u = RedPitayaDAQServer.readData(daq.rpc, startFrame, numFrames, numBlockAverages, 1, useCalibration = true)

  @info "size u in readData: $(size(u))"
  uMeas = u[:,channelIdx(daq, daq.rxChanIDs),:,:]u"V"
  uRef = u[:,channelIdx(daq, daq.refChanIDs),:,:]u"V"

  # lostSteps = numLostStepsSlowADC(master(daq.rpc))
  # if lostSteps > 0
  #   @error "WE LOST $lostSteps SLOW DAC STEPS!"
  # end

  @debug size(uMeas) size(uRef)

  return uMeas, uRef
end

function readDataPeriods(daq::RedPitayaDAQ, numPeriods, startPeriod, acqNumAverages)
  u = RedPitayaDAQServer.readPeriods(daq.rpc, startPeriod, numPeriods, acqNumAverages, useCalibration = true)

  uMeas = u[:,channelIdx(daq, daq.rxChanIDs),:]
  uRef = u[:,channelIdx(daq, daq.refChanIDs),:]

  return uMeas, uRef
end

numTxChannelsTotal(daq::RedPitayaDAQ) = numChan(daq.rpc)
numRxChannelsTotal(daq::RedPitayaDAQ) = numChan(daq.rpc)
numTxChannelsActive(daq::RedPitayaDAQ) = numChan(daq.rpc) #TODO: Currently, all available channels are active
numRxChannelsActive(daq::RedPitayaDAQ) = numRxChannelsReference(daq)+numRxChannelsMeasurement(daq)
numRxChannelsReference(daq::RedPitayaDAQ) = length(daq.refChanIDs)
numRxChannelsMeasurement(daq::RedPitayaDAQ) = length(daq.rxChanIDs)
numComponentsMax(daq::RedPitayaDAQ) = 4
canPostpone(daq::RedPitayaDAQ) = true
canConvolute(daq::RedPitayaDAQ) = false


######## OLD #########
function disconnect(daq::RedPitayaDAQ)
  RedPitayaDAQServer.disconnect(daq.rpc)
end
