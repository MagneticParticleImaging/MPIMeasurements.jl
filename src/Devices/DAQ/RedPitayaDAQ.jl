export RedPitayaDAQParams, RedPitayaDAQ, disconnect, setSlowDAC, getSlowADC, connectToServer,
       setTxParamsAll, disconnect
using RedPitayaDAQServer

@enum RPTriggerMode begin
  INTERNAL
  EXTERNAL
end

Base.@kwdef mutable struct RedPitayaDAQParams <: DAQParams
  "All configured channels of this DAQ device."
  channels::Dict{String, DAQChannelParams}

  "IPs of the Red Pitayas"
  ips::Vector{String}
  "Trigger mode of the Red Pitayas. Default: `EXTERNAL`."
  triggerMode::RPTriggerMode = EXTERNAL
  "Time to wait after a reset has been issued."
  resetWaittime::typeof(1.0u"s") = 45u"s"
  calibFFCurrentToVolt::Vector{Float32}
  calibIntToVolt::Array{Float32}
  ffRampUpFraction::Float32 = 1.0 # TODO RampUp + RampDown, could be a Union of Float or Vector{Float} and then if Vector [1] is up and [2] down
  ffRampUpTime::Float32 = 0.1 # and then the actual ramping could be a param of RedPitayaDAQ
  passPDMToFastDAC::Vector{Bool}
end

Base.@kwdef struct RedPitayaTxChannelParams <: TxChannelParams
  channelIdx::Int64
  limitPeak::typeof(1.0u"V")
  sinkImpedance::SinkImpedance = SINK_HIGH
  allowedWaveforms::Vector{Waveform} = [WAVEFORM_SINE]
  feedback::Union{DAQFeedback, Nothing} = nothing
  calibration::Union{typeof(1.0u"V/T"), Nothing} = nothing
end

Base.@kwdef struct RedPitayaLUTChannelParams <: DAQChannelParams
  channelIdx::Int64
  calibration::Union{typeof(1.0u"V/T"), typeof(1.0u"V/A"), Nothing} = nothing
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function RedPitayaDAQParams(dict::Dict{String, Any})
  return createDAQParams(RedPitayaDAQParams, dict)
end

function createDAQChannels(::Type{RedPitayaDAQParams}, dict::Dict{String, Any})
  # TODO This is mostly copied from createDAQChannels, maybe manage to get rid of the duplication
  channels = Dict{String, DAQChannelParams}()
  for (key, value) in dict
    splattingDict = Dict{Symbol, Any}()
    if value["type"] == "tx"
      splattingDict[:channelIdx] = value["channel"]
      splattingDict[:limitPeak] = uparse(value["limitPeak"])

      if haskey(value, "sinkImpedance")
        splattingDict[:sinkImpedance] = value["sinkImpedance"] == "FIFTY_OHM" ? SINK_FIFTY_OHM : SINK_HIGH
      end

      if haskey(value, "allowedWaveforms")
        splattingDict[:allowedWaveforms] = toWaveform.(value["allowedWaveforms"])
      end

      if haskey(value, "feedback")
        channelID=value["feedback"]["channelID"]
        calibration=uparse(value["feedback"]["calibration"])

        splattingDict[:feedback] = DAQFeedback(channelID=channelID, calibration=calibration)
      end

      if haskey(value, "calibration")
        splattingDict[:calibration] = uparse.(value["calibration"])
      end

      if haskey(value, "passPDMToFastDAC")
        splattingDict[:passPDMToFastDAC] = value["passPDMToFastDAC"]
      end

      channels[key] = RedPitayaTxChannelParams(;splattingDict...)
    elseif value["type"] == "rx"
      channels[key] = DAQRxChannelParams(channelIdx=value["channel"])
    elseif value["type"] == "txSlow"
      calib = nothing
      if haskey(value, "calibration")
        calib = uparse.(value["calibration"])
      end
      channels[key] = RedPitayaLUTChannelParams(channelIdx=value["channel"], calibration = calib)
    end
  end

  return channels
end

Base.@kwdef mutable struct RedPitayaDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::RedPitayaDAQParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  "Reference to the Red Pitaya cluster"
  rpc::Union{RedPitayaCluster, Nothing} = nothing
  rpv::Union{RedPitayaClusterView, Nothing} = nothing

  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []
  acqSeq::Union{Vector{AbstractSequence}, Nothing} = nothing
  samplesPerStep::Int32 = 0
  decimation::Int32 = 64
  samplingPoints::Int = 1
  sampleAverages::Int = 1
  acqPeriodsPerFrame::Int = 1
  acqPeriodsPerPatch::Int = 1
  acqNumFrames::Int = 1
  acqNumFrameAverages::Int = 1
  acqNumAverages::Int = 1
end

function init(daq::RedPitayaDAQ)
  @info "Initializing Red Pitaya DAQ with ID `$(daq.deviceID)`."

  # Restart the DAQ if necessary
  try
    daq.rpc = RedPitayaCluster(daq.params.ips)
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

  try
    daq.params.calibIntToVolt = reshape(daq.params.calibIntToVolt, 2, :)
  catch e
    @error e
  end

  #setACQParams(daq)
  masterTrigger(daq.rpc, false)
  triggerMode(daq.rpc, string(daq.params.triggerMode))
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "STANDARD")
  #masterTrigger(daq.rpc, true)

  daq.present = true
end

neededDependencies(::RedPitayaDAQ) = []
optionalDependencies(::RedPitayaDAQ) = [TxDAQController, SurveillanceUnit]

Base.close(daq::RedPitayaDAQ) = daq.rpc


#### Sequence ####
function setSequenceParams(daq::RedPitayaDAQ, luts::Vector{Union{Nothing, Array{Float64}}}, enableLuts::Vector{Union{Nothing, Array{Bool}}})
  if length(luts) != length(daq.rpc)
    throw(DimensionMismatch("$(length(luts)) LUTs do not match $(length(daq.rpc)) RedPitayas"))
  end
  if length(enableLuts) != length(daq.rpc)
    throw(DimensionMismatch("$(length(enableLuts)) enableLUTs do not match $(length(daq.rpc)) RedPitayas"))
  end
  # Restrict to sequences of equal length, not a requirement of RedPitayaDAQServer, but of MPIMeasurements for simplicityacqSeq
  sizes = map(x-> size(x, 2) , filter(!isnothing, luts))
  if minimum(sizes) != maximum(sizes)
    throw(DimensionMismatch("LUTs do not have equal amount of steps"))
  end

  @info "Set sequence params"

  stepsPerRepetition = div(daq.acqPeriodsPerFrame, daq.acqPeriodsPerPatch)
  samplesPerSlowDACStep(daq.rpc, div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition))
  daq.samplesPerStep = samplesPerSlowDACStep(daq.rpc)
  clearSequence(daq.rpc)

  acqSeq = []
  for (i, rp) in enumerate(daq.rpc)
    lut = luts[i]
    enableLUT = enableLuts[i]
    if !isnothing(lut)
      numSlowDACChan(rp, size(lut, 1))
      @show lut
      #TODO IMPLEMENT SHORTER RAMP DOWN TIMING FOR SYSTEM MATRIX
      rpSeq = ArbitrarySequence(lut, enableLUT, stepsPerRepetition, daq.acqNumFrames*daq.acqNumFrameAverages,
                      computeRamping(daq.rpc, size(lut, 2), daq.params.ffRampUpTime, daq.params.ffRampUpFraction))
      push!(acqSeq, rpSeq)
      appendSequence(rp, rpSeq)
      # TODO enableLuts not yet implemented
    else
      # TODO What to do in this case, see maybe fill with zeros in other setSequenceParams
      # PauseSequence()
    end
  end

  daq.acqSeq = isempty(acqSeq) ? nothing : acqSeq

end
function setSequenceParams(daq::RedPitayaDAQ, sequence::Sequence)
  luts = Array{Union{Nothing, Array{Float64}}}(nothing, length(daq.rpc))
  enableLuts = Array{Union{Nothing, Array{Bool}}}(nothing, length(daq.rpc))

  lutChannels = [channel for channel in daq.params.channels if channel[2] isa RedPitayaLUTChannelParams]
  seqChannels = acyclicElectricalTxChannels(sequence)
  channelMapping = []
  for channel in seqChannels
    index = findfirst(x-> id(channel) == x[1], lutChannels)
    if !isnothing(index)
      push!(channelMapping, (lutChannels[index][2], channel))
    else
      throw(ScannerConfigurationError("No txSlow Channel defined for Field channel $(id(channel))"))
    end
  end

  @show channelMapping
  for rp in 1:length(daq.rpc)
    start = (rp - 1) * 4 + 1
    currentPossibleChannels = collect(start:start+3)
    currentMapping = [(lut, seq) for (lut, seq) in channelMapping if lut.channelIdx in currentPossibleChannels]
    if !isempty(currentMapping)
      lut = createLUT(start, currentMapping)
      luts[rp] = lut
    end
  end
  daq.acqPeriodsPerPatch = acqNumPeriodsPerPatch(sequence)
  @show luts
  setSequenceParams(daq, luts, enableLuts)
end

function createLUT(start, channelMapping)
  channelMapping = sort(channelMapping, by = x -> x[1].channelIdx)
  lutValues = []
  lutIdx = []
  for (lutChannel, seqChannel) in channelMapping
    tempValues = MPIFiles.values(seqChannel)
    if !isnothing(lutChannel.calibration)
      tempValues = tempValues.*lutChannel.calibration
    end
    tempValues = ustrip.(u"V", tempValues)
    push!(lutValues, tempValues)
    push!(lutIdx, lutChannel.channelIdx)
  end

  # Idx from 1 to 4
  lutIdx = (lutIdx.-start).+1
  # Fill skipped channels with 0.0, assumption: size of all lutValues is equal
  lut = zeros(Float32, maximum(lutIdx), size(lutValues[1], 1))
  for (i, lutIndex) in enumerate(lutIdx)
    lut[lutIndex, :] = lutValues[i]
  end
  return lut
end

function prepareSequence(daq::RedPitayaDAQ, sequence::Sequence)
  if !isnothing(daq.acqSeq)
    @info "Preparing sequence"
    success = RedPitayaDAQServer.prepareSequence(daq.rpc)
    if !success
      @warn "Failed to prepare sequence"
    end
  end
end

function endSequence(daq::RedPitayaDAQ, endFrame)
  sampPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  endSample = (endFrame + 1) * sampPerFrame
  wp = currentWP(daq.rpc)
  # Wait for sequence to finish
  numQueries = 0
    while wp < endSample
      sampleDiff = endSample - wp
      waitTime = (sampleDiff / (125e6/daq.decimation))
      sleep(waitTime) # Queries are expensive, try to sleep to minimize amount of queries
      numQueries += 1
      wp = currentWP(daq.rpc)
  end
  stopTx(daq)
end

function getFrameTiming(daq::RedPitayaDAQ)
  # TODO How to signal end of sequences without any LUTs
  startSample = RedPitayaDAQServer.start(daq.acqSeq[1]) * daq.samplesPerStep
  startFrame = div(startSample, samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
  endFrame = div((length(daq.acqSeq[1]) * daq.samplesPerStep), samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
  return startFrame, endFrame
end

#### Producer/Consumer ####
mutable struct RedPitayaAsyncBuffer <: AsyncBuffer
  samples::Union{Matrix{Int16}, Nothing}
  performance::Vector{Vector{PerformanceData}}
end
AsyncBuffer(daq::RedPitayaDAQ) = RedPitayaAsyncBuffer(nothing, Vector{Vector{PerformanceData}}(undef, 1))

channelType(daq::RedPitayaDAQ) = SampleChunk

function updateAsyncBuffer!(buffer::RedPitayaAsyncBuffer, chunk)
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
end
end

function frameAverageBufferSize(daq::RedPitayaDAQ, frameAverages)
  return samplesPerPeriod(daq.rpc), length(daq.rxChanIDs), periodsPerFrame(daq.rpc), frameAverages
end

function startProducer(channel::Channel, daq::RedPitayaDAQ, numFrames)
  startFrame, endFrame = getFrameTiming(daq)
  startTx(daq)

  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  startSample = startFrame * samplesPerFrame
  samplesToRead = samplesPerFrame * numFrames
  chunkSize = Int(ceil(0.1 * (125e6/daq.decimation)))

  rpu = daq.rpc
  if !isnothing(daq.rpv)
    rpu = daq.rpv
  end

  # Start pipeline
  @info "Pipeline started"
  try
    readPipelinedSamples(rpu, startSample, samplesToRead, channel, chunkSize = chunkSize)
  catch e
    @error e
    # TODO disconnect and reconnect to recover from open pipeline
    @info "Attempting reconnect to reset pipeline"
    daq.rpc = RedPitayaCluster(daq.params.ips)
    daq.rpv = nothing
  end
  @info "Pipeline finished"
  return endFrame
end


function convertSamplesToFrames!(buffer::RedPitayaAsyncBuffer, daq::RedPitayaDAQ)
  unusedSamples = buffer.samples
  samples = buffer.samples
  frames = nothing
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  samplesInBuffer = size(samples)[2]
  framesInBuffer = div(samplesInBuffer, samplesPerFrame)

  if framesInBuffer > 0
      samplesToConvert = view(samples, :, 1:(samplesPerFrame * framesInBuffer))
      chan = numChan(daq.rpc)
      if !isnothing(daq.rpv)
        chan = numChan(daq.rpv)
      end
      frames = convertSamplesToFrames(samplesToConvert, chan, samplesPerPeriod(daq.rpc), periodsPerFrame(daq.rpc), framesInBuffer, daq.acqNumAverages, 1)

      # TODO move this to ref and meas conversion and get the params from the channels
      c = daq.params.calibIntToVolt #is calibIntToVolt ever sanity checked?
      for d = 1:size(frames, 2)
        frames[:, d, :, :] .*= c[1,d]
        frames[:, d, :, :] .+= c[2,d]
      end

      if (samplesPerFrame * framesInBuffer) + 1 <= samplesInBuffer
          unusedSamples = samples[:, (samplesPerFrame * framesInBuffer) + 1:samplesInBuffer]
      else
        unusedSamples = nothing
      end

  end

  buffer.samples = unusedSamples
  return frames
end

function retrieveMeasAndRef!(buffer::RedPitayaAsyncBuffer, daq::RedPitayaDAQ)
  frames = convertSamplesToFrames!(buffer, daq)
  uMeas = nothing
  uRef = nothing
  if !isnothing(frames)
    rxIds = channelIdx(daq, daq.rxChanIDs)
    refIds = channelIdx(daq, daq.refChanIDs)
    # Map channel index to their respective index in the view
    if !isnothing(daq.rpv)
      rxIds = map(x->clusterToView(daq.rpv, x), rxIds)
      refIds = map(x->clusterToView(daq.rpv, x), rxIds)
    end
    uMeas = frames[:,rxIds,:,:]
    uRef = frames[:, refIds,:,:]
  end
  return uMeas, uRef
end

#### Tx and Rx
function setup(daq::RedPitayaDAQ, sequence::Sequence)
  setupRx(daq, sequence)
  setupTx(daq, sequence)
end

function setupTx(daq::RedPitayaDAQ, sequence::Sequence)
  @info "Setup tx"
  periodicChannels = periodicElectricalTxChannels(sequence)

  if any([length(component.amplitude) > 1 for channel in periodicChannels for component in channel.components])
    error("The Red Pitaya DAQ cannot work with more than one period in a frame or frequency sweeps yet.")
  end

  # Iterate over sequence(!) channels
  for channel in periodicChannels
    channelIdx_ = channelIdx(daq, id(channel)) # Get index from scanner(!) channel

    offsetVolts = offset(channel)*calibration(daq, id(channel))
    offsetDAC(daq.rpc, channelIdx_, ustrip(u"V", offsetVolts))
    #jumpSharpnessDAC(daq.rpc, channelIdx_, daq.params.jumpSharpness) # TODO: Can we determine this somehow from the sequence?

    for (idx, component) in enumerate(components(channel))
      freq = ustrip(u"Hz", txBaseFrequency(sequence)) / divider(component)
      frequencyDAC(daq.rpc, channelIdx_, idx, freq)
    end

    # In the Red Pitaya, the signal type can only be set per channel
    waveform_ = unique([waveform(component) for component in components(channel)])
    if length(waveform_) == 1
      if !isWaveformAllowed(daq, id(channel), waveform_[1])
        throw(SequenceConfigurationError("The channel of sequence `$(name(sequence))` with the ID `$(id(channel))` "*
                                       "defines a waveforms of $waveform_, but the scanner channel does not allow this."))
      end
      waveform_ = uppercase(fromWaveform(waveform_[1]))
      signalTypeDAC(daq.rpc, channelIdx_, waveform_)
    else
      throw(SequenceConfigurationError("The channel of sequence `$(name(sequence))` with the ID `$(id(channel))` "*
                                       "defines different waveforms in its components. This is not supported "*
                                       "by the Red Pitaya."))
    end
  end

  pass = isempty(daq.params.passPDMToFastDAC) ? [false for i = 1:length(daq.rpc)] : daq.params.passPDMToFastDAC
  @show pass
  passPDMToFastDAC(daq.rpc, pass)

  #setSequenceParams(daq, sequence) # This might need to be removed for calibration measurement time savings
end

function setupRx(daq::RedPitayaDAQ)
  @info "Setup rx"
  decimation(daq.rpc, daq.decimation)
  samplesPerPeriod(daq.rpc, daq.samplingPoints * daq.acqNumAverages)
  periodsPerFrame(daq.rpc, daq.acqPeriodsPerFrame)
  #numSlowADCChan(daq.rpc, 4) # Not used as far as I know
end
function setupRx(daq::RedPitayaDAQ, sequence::Sequence)
  @assert txBaseFrequency(sequence) == 125.0u"MHz" "The base frequency is fixed for the Red Pitaya "*
  "and must thus be 125 MHz and not $(txBaseFrequency(sequence))."

  # The decimation can only be a power of 2 beginning with 8
  decimation_ = upreferred(txBaseFrequency(sequence)/rxSamplingRate(sequence))
  if decimation_ in [2^n for n in 3:8]
    daq.decimation = decimation_
  else
    throw(ScannerConfigurationError("The decimation derived from the rx bandwidth of $(rxBandwidth(sequence)) and "*
      "the base frequency of $(txBaseFrequency(sequence)) has a value of $decimation_ "*
      "but has to be a power of 2"))
  end

  daq.acqNumFrames = acqNumFrames(sequence)
  daq.acqNumFrameAverages = acqNumFrameAverages(sequence)
  daq.acqNumAverages = acqNumAverages(sequence)
  daq.samplingPoints = rxNumSamplesPerPeriod(sequence)
  daq.acqPeriodsPerFrame = acqNumPeriodsPerFrame(sequence)

  daq.rxChanIDs = []
  for channel in rxChannels(sequence)
    push!(daq.rxChanIDs, id(channel))
  end

  # TODO possibly move some of this into abstract daq
  daq.refChanIDs = []
  txChannels = [channel[2] for channel in daq.params.channels if channel[2] isa TxChannelParams]
  daq.refChanIDs = unique([tx.feedback.channelID for tx in txChannels if !isnothing(tx.feedback)])

  # Construct view to save bandwidth
  rxIDs = sort(union(channelIdx(daq, daq.rxChanIDs), channelIdx(daq, daq.refChanIDs)))
  selection = [false for i = 1:length(daq.rpc)]
  for i in map(x->div(x -1, 2) + 1, rxIDs)
    selection[i] = true
  end
  daq.rpv = RedPitayaClusterView(daq.rpc, selection)

  setupRx(daq)
end
function setupRx(daq::RedPitayaDAQ, decimation, numSamplesPerPeriod, numPeriodsPerFrame, numFrames; numFrameAverage=1, numAverages=1)
  daq.decimation = decimation
  daq.samplingPoints = numSamplesPerPeriod
  daq.acqPeriodsPerFrame = numPeriodsPerFrame
  daq.acqNumFrames = numFrames
  daq.acqNumFrameAverages = numFrameAverage
  daq.acqNumAverages = numAverages
  daq.rpv = nothing
  setupRx(daq)
end

# Starts both tx and rx in the case of the Red Pitaya since both are entangled by the master trigger.
function startTx(daq::RedPitayaDAQ)
  startADC(daq.rpc)
  masterTrigger(daq.rpc, true)
  @info "Started tx"
end

function stopTx(daq::RedPitayaDAQ)
  #setTxParams(daq, zeros(ComplexF64, numTxChannels(daq),numTxChannels(daq)))
  stopADC(daq.rpc)
  masterTrigger(daq.rpc, false)
  @info "Stopped tx"
  #RedPitayaDAQServer.disconnect(daq.rpc)
end

function prepareControl(daq::RedPitayaDAQ)
  clearSequence(daq.rpc)
end

function prepareTx(daq::RedPitayaDAQ, sequence::Sequence)
  stopTx(daq)
  @info "Preparing amplitude and phase"
  allAmps  = Dict{String, Vector{typeof(1.0u"V")}}()
  allPhases = Dict{String, Vector{typeof(1.0u"rad")}}()
  for channel in periodicElectricalTxChannels(sequence)
    name = id(channel)
    amps = []
    phases = []
    for comp in components(channel)
      # Lengths check == 1 happens in setupTx already
      amp = amplitude(comp)
      if dimension(amp) == dimension(1.0u"T")
        amp = (amp * calibration(daq, name))
      end
      push!(amps, amp)
      push!(phases, phase(comp))
    end

    allAmps[name] = amps

    allPhases[name] = phases

  end
  setTxParams(daq, allAmps, allPhases)
end

"""
Set the amplitude and phase for all the selected channels.

Note: `amplitudes` and `phases` are defined as a dictionary of
vectors, since every channel referenced by the dict's key could
have a different amount of components.
"""
function setTxParams(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{Union{Float32, Nothing}}}, phases::Dict{String, Vector{Union{Float32, Nothing}}})
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

  for (channelID, components_) in phases
    for (componentIdx, phase_) in enumerate(components_)
      if !isnothing(phase_)
        phaseDAC(daq.rpc, channelIdx(daq, channelID), componentIdx, phase_)
      end
    end
  end

  for (channelID, components_) in amplitudes
    for (componentIdx, amplitude_) in enumerate(components_)
      if !isnothing(amplitude_)
        amplitudeDAC(daq.rpc, channelIdx(daq, channelID), componentIdx, amplitude_)
      end
    end
  end
end

function setTxParams(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{typeof(1.0u"V")}}, phases::Dict{String, Vector{typeof(1.0u"rad")}}; convolute=true)
  # Determine the worst case voltage per channel
  # Note: this would actually need a fourier synthesis with the given signal type,
  # but I don't think this is necessary
  for (channelID, components_) in amplitudes
    channelVoltage = 0
    for amplitude_ in components_
      channelVoltage += ustrip(u"V", amplitude_)
    end

    if channelVoltage >= ustrip(u"V", limitPeak(daq, channelID))
      error("This should never happen!!! \nTx voltage on channel with ID `$channelID` is above the limit with a voltage of $channelVoltage.")
    end
  end

  for (channelID, components_) in phases
    for (componentIdx, phase_) in enumerate(components_)
      phaseDAC(daq.rpc, channelIdx(daq, channelID), componentIdx, ustrip(u"rad", phase_))
    end
  end

  for (channelID, components_) in amplitudes
    for (componentIdx, amplitude_) in enumerate(components_)
        amplitudeDAC(daq.rpc, channelIdx(daq, channelID), componentIdx, ustrip(u"V", amplitude_))
    end
  end
end

currentFrame(daq::RedPitayaDAQ) = RedPitayaDAQServer.currentFrame(daq.rpc)
currentPeriod(daq::RedPitayaDAQ) = RedPitayaDAQServer.currentPeriod(daq.rpc)

function readData(daq::RedPitayaDAQ, startFrame::Integer, numFrames::Integer, numBlockAverages::Integer=1)
  u = RedPitayaDAQServer.readData(daq.rpc, startFrame, numFrames, numBlockAverages, 1)

  @info "size u in readData: $(size(u))"
  # TODO: Should be replaced when https://github.com/tknopp/RedPitayaDAQServer/pull/32 is resolved
  c = repeat([0.00012957305 0.015548877], outer=2*10)' # TODO: This is just an arbitrary number. The whole part should be replaced by calibration values coming from EEPROM.
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

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
  u = RedPitayaDAQServer.readDataPeriods(daq.rpc, startPeriod, numPeriods, acqNumAverages)

  # TODO: Should be replaced when https://github.com/tknopp/RedPitayaDAQServer/pull/32 is resolved
  #c = repeat([0.00012957305 0.015548877], outer=2*10)' # TODO: This is just an arbitrary number. The whole part should be replaced by calibration values coming from EEPROM.
  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

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