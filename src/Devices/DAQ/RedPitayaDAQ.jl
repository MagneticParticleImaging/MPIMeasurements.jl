# import RedPitayaDAQServer: currentFrame, currentPeriod, readData, readDataPeriods,
#                            setSlowDAC, getSlowADC, enableSlowDAC, readDataSlow

export RedPitayaDAQParams, RedPitayaDAQ, disconnect, setSlowDAC, getSlowADC, connectToServer,
       setTxParamsAll, disconnect
using RedPitayaDAQServer

@enum RPTriggerMode begin
  INTERNAL
  EXTERNAL
end

Base.@kwdef struct RedPitayaDAQParams <: DAQParams
  "All configured channels of this DAQ device."
  channels::Dict{String, DAQChannelParams}

  "IPs of the Red Pitayas"
  ips::Vector{String}
  "Trigger mode of the Red Pitayas. Default: `EXTERNAL`."
  triggerMode::RPTriggerMode = EXTERNAL
  "Time to wait after a reset has been issued."
  resetWaittime::typeof(1.0u"s") = 45u"s"
  calibFFCurrentToVolt::Vector{Float32} = [0.0]
  ffRampUpFraction::Float32 = 1.0 # TODO RampUp + RampDown, could be a Union of Float or Vector{Float} and then if Vector [1] is up and [2] down
  ffRampUpTime::Float32 = 0.1 # and then the actual ramping could be a param of RedPitayaDAQ
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function RedPitayaDAQParams(dict::Dict{String, Any})
  return createDAQParams(RedPitayaDAQParams, dict)
end

Base.@kwdef mutable struct RedPitayaDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::RedPitayaDAQParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  "Reference to the Red Pitaya cluster"
  rpc::Union{RedPitayaCluster, Nothing} = nothing

  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []
  acqSeq::Union{AbstractSequence, Nothing} = nothing
  samplesPerStep::Int32 = 0
  decimation::Int32 = 64
  passPDMToFastDAC::Vector{Bool} = []
  samplingPoints::Int = 1
  sampleAverages::Int = 1
  acqPeriodsPerFrame::Int = 1
  acqPeriodsPerPatch::Int = 1
  acqNumFrames::Int = 1
  acqNumFrameAverages::Int = 1
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

  #setACQParams(daq)
  masterTrigger(daq.rpc, false)
  triggerMode(daq.rpc, string(daq.params.triggerMode))
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "STANDARD")
  #masterTrigger(daq.rpc, true)
end

checkDependencies(daq::RedPitayaDAQ) = true


#### Sequence ####
function setSequenceParams(daq::RedPitayaDAQ, lut, enableLUT = nothing)
  stepsPerRepetition = div(daq.acqPeriodsPerFrame, daq.acqNumPeriodsPerPatch)
  samplesPerSlowDACStep(daq.rpc, div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition))
  daq.samplesPerStep = samplesPerSlowDACStep(daq.rpc)
  clearSequence(daq.rpc)

  if !isnothing(lut) 
    numSlowDACChan(master(daq.rpc), size(lut, 1))
    lut = lut.*daq.params.calibFFCurrentToVolt
    #TODO IMPLEMENT SHORTER RAMP DOWN TIMING FOR SYSTEM MATRIX
    #TODO Distribute sequence on multiple redpitayas, not all the same
    daq.acqSeq = ArbitrarySequence(lut, enableLUT, stepsPerRepetition,
    daq.acqNumFrames*daq.acqNumFrameAverages, computeRamping(daq.rpc, size(lut, 2), daq.params.ffRampUpTime, daq.params.ffRampUpFraction))
    appendSequence(master(daq.rpc), daq.acqSeq)
  else
    numSlowDACChan(master(daq.rpc), 0)
    daq.acqSeq = nothing
  end
end
function setSequenceParams(daq::RedPitayaDAQ, sequence::Sequence)
  lut = nothing
  channels = acyclicElectricalTxChannels(sequence)
  temp = [values(channel) for channel in channels]
  if length(temp) > 0
    if length(temp) == 1
      lut = [ustrip(u"V", x) for x in temp[1]]
    else if length(temp) == 2
      lut1 = [ustrip(u"V", x) for x in temp[1]]
      lut2 = [ustrip(u"V", x) for x in temp[2]]
      lut = collect(cat(lut1,lut2,dims=2))
    end
    lut = lut .* daq.params.calibFFCurrentToVolt
  end
  daq.acqPeriodsPerPatch = acqNumPeriodsPerPatch(sequence)
  setSequenceParams(daq, lut, nothing)
end

function prepareSequence(daq::RedPitayaDAQ, sequence::Sequence)
  if !isnothing(daq.acqSeq)
    @info "Preparing sequence"
    success = RedPitayaDAQServer.prepareSequence(daq.rpc)
    if !success
      @warn "Failed to prepare sequence"
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
      waitTime = (sampleDiff / (125e6/daq.params.decimation))
      sleep(waitTime) # Queries are expensive, try to sleep to minimize amount of queries
      numQueries += 1
      wp = currentWP(daq.rpc)
  end 
  stopTx(daq)
end

function getFrameTiming(daq::RedPitayaDAQ)
  startSample = start(daq.acqSeq) * daq.samplesPerStep
  startFrame = div(startSample, samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
  endFrame = div((length(daq.acqSeq) * daq.samplesPerStep), samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
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
  return samplesPerPeriod(daq.rpc), numRxChannels(daq), periodsPerFrame(daq.rpc), frameAverages
end

function startProducer(channel::Channel, daq::RedPitayaDAQ, numFrames)
  startFrame, endFrame = getFrameTiming(daq)
  startTx(daq)
    
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  startSample = startFrame * samplesPerFrame
  samplesToRead = samplesPerFrame * numFrames
  chunkSize = Int(ceil(0.1 * (125e6/daq.decimation)))

  # Start pipeline
  @info "Pipeline started"
  try 
    readPipelinedSamples(daq.rpc, startSample, samplesToRead, channel, chunkSize = chunkSize) 
  catch e
    @error e 
  end
  @info "Pipeline finished"
  return endFrame
end

function setup(daq::RedPitayaDAQ, sequence::Sequence)
  setupTx(daq, sequence)
  setupRx(daq, sequence)
end

function setupTx(daq::RedPitayaDAQ, sequence::Sequence)
  @assert txBaseFrequency(sequence) == 125.0u"MHz" "The base frequency is fixed for the Red Pitaya "*
                                                   "and must thus be 125 MHz and not $(txBaseFrequency(sequence))."
  
  # The decimation can only be a power of 2 beginning with 8
  decimation_ = upreferred(txBaseFrequency(sequence)/rxBandwidth(sequence)/2)
  if decimation_ in [2^n for n in 3:8]
    decimation(daq.rpc, decimation_)
  else
    throw(ScannerConfigurationError("The decimation derived from the rx bandwidth of $(rxBandwidth(sequence)) and "*
                                    "the base frequency of $(txBaseFrequency(sequence)) has a value of $decimation_ "*
                                    "but has to be a power of 2"))
  end

  channels = electricalTxChannels(sequence)
  periodicChannels = [channel for channel in channels if channel isa PeriodicElectricalChannel]
  stepwiseChannels = [channel for channel in channels if channel isa StepwiseElectricalTxChannel]

  if !isempty(stepwiseChannels)
    @warn "The Red Pitaya DAQ can only process periodic channels. Other channels are ignored."
  end

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
      frequencyDAC(daq.rpc, channelIdx_, idx, divider(component))
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

  #TODO: Should be derived from sequence when I have understood how the passing works
  #passPDMToFastDAC(daq.rpc, daq.params.passPDMToFastDAC)  
  #slowDACStepsPerFrame(daq.rpc, div(daq.params.acqNumPeriodsPerFrame,daq.params.acqNumPeriodsPerPatch))
 
  # if !isempty(daq.params.acqFFValues) 
  #   numSlowDACChan(master(daq.rpc), daq.params.acqNumFFChannels)
  #   setSlowDACLUT(master(daq.rpc), daq.params.acqFFValues.*daq.params.calibFFCurrentToVolt)
  #   if !isempty(daq.params.acqEnableSequence)
  #     enableDACLUT(master(daq.rpc), daq.params.acqEnableSequence)
  #   else # We might want to solve this differently
  #     enableDACLUT(master(daq.rpc), ones(Bool, length(daq.params.acqFFValues)))
  #   end
  # else
  #   numSlowDACChan(master(daq.rpc), 0)
  # end

  # numSlowADCChan(daq.rpc, 4)

  return nothing
end

function setupRx(daq::RedPitayaDAQ, sequence::Sequence)
  samplesPerPeriod(daq.rpc, rxNumSamplesPerPeriod(sequence))
  periodsPerFrame(daq.rpc, acqNumPeriodsPerFrame(sequence))
  
  for channel in rxChannels(sequence)
    try
      push!(daq.rxChanIDs, id(channel))
    catch e
      if e isa KeyError
        throw(ScannerConfigurationError("The given sequence `$(name(sequence))` requires a receive "*
                                        "channel with ID `$(channel.id)`, which is not defined by "*
                                        "the scanner configuration."))
      else
        rethrow()
      end
    end
  end
end

# Starts both tx and rx in the case of the Red Pitaya since both are entangled by the master trigger.
function startTx(daq::RedPitayaDAQ)
  masterTrigger(daq.rpc, false)
  startADC(daq.rpc)
  masterTrigger(daq.rpc, true)

  sleepTime = 0.1
  breakTime = 2.0
  loopCounter = 0
  while RedPitayaDAQServer.currentPeriod(daq.rpc) < 1
    sleep(sleepTime)
    loopCounter += 1
    if loopCounter*sleepTime > breakTime
      @error "The current period did not increase within $breakTime. Something is wrong with the trigger setup."
      break
    end
  end
  return nothing
end

function stopTx(daq::RedPitayaDAQ)
  #setTxParams(daq, zeros(ComplexF64, numTxChannels(daq),numTxChannels(daq)))
  stopADC(daq.rpc)
  masterTrigger(daq.rpc, false)
  #RedPitayaDAQServer.disconnect(daq.rpc)
end

"""
Set the amplitude and phase for all the selected channels.

Note: `amplitudes` and `phases` are defined as a dictionary of
vectors, since every channel referenced by the dict's key could
have a different amount of components.
"""
function setTxParams(daq::RedPitayaDAQ, amplitudes::Dict{String, Vector{typeof(1.0u"V")}}, phases::Dict{String, Vector{typeof(1.0u"rad")}}; convolute=true)
  # Determine the worst case voltage per channel 
  # Note: this would actually need a fourier synthesis with the given signal type,
  # but I don't think this is necessary
  for (channelID, components_) in amplitudes
    channelVoltage = 0
    for (componentIdx, amplitude_) in components_
      channelVoltage += amplitude_
    end
      
    if channelVoltage >= limitPeak(daq, channelID)
      error("This should never happen!!! \nTx voltage on channel with ID `$channelID` is above the limit.")
    end
  end
    
  
  for (channelID, components_) in phases
    for (componentIdx, phase_) in components_
      phaseDAC(daq.rpc, channelIdx(channelID), componentIdx, ustrip(u"rad", phase_))
    end
  end

  for (channelID, components_) in amplitudes
    for (componentIdx, amplitude_) in components_

      #if postpone
      # The following is a very bad and dangerous hack. Right now postponing the activation of 
      # fast Tx channels into the sequence does not work on slave RPs. For this reason we switch it on there
      # directly
      # Note: The Red Pitaya does not allow for convoltution of the signal. Falls back to postponing.
      if convolute && channelIdx(channelID) <= 2   
        amplitudeDACNext(daq.rpc, channelIdx(channelID), componentIdx, ustrip(u"V", amplitude_)) 
      else
        amplitudeDAC(daq.rpc, channelIdx(channelID), componentIdx, ustrip(u"V", amplitude_))
      end
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

function readDataPeriods(daq::RedPitayaDAQ, numPeriods, startPeriod)
  u = RedPitayaDAQServer.readDataPeriods(daq.rpc, startPeriod, numPeriods, daq.params.acqNumAverages)

  # TODO: Should be replaced when https://github.com/tknopp/RedPitayaDAQServer/pull/32 is resolved
  c = repeat([0.00012957305 0.015548877], outer=2*10)' # TODO: This is just an arbitrary number. The whole part should be replaced by calibration values coming from EEPROM.
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


function updateParams!(daq::RedPitayaDAQ, params_::Dict)
  connect(daq.rpc)
  
  daq.params = DAQParams(params_)
  
  setACQParams(daq)
end


function calibIntToVoltRx(daq::RedPitayaDAQ)
  return daq.params.calibIntToVolt[:,daq.params.rxChanIdx]
end

function calibIntToVoltRef(daq::RedPitayaDAQ)
  return daq.params.calibIntToVolt[:,daq.params.refChanIdx]
end





function disconnect(daq::RedPitayaDAQ)
  RedPitayaDAQServer.disconnect(daq.rpc)
end

function setSlowDAC(daq::RedPitayaDAQ, value, channel)
  setSlowDAC(daq.rpc, channel, value.*daq.params.calibFFCurrentToVolt[channel])

  return nothing
end

function getSlowADC(daq::RedPitayaDAQ, channel)
  return getSlowADC(daq.rpc, channel)
end

enableSlowDAC(daq::RedPitayaDAQ, enable::Bool, numFrames=0,
              ffRampUpTime=0.4, ffRampUpFraction=0.8) =
            enableSlowDAC(daq.rpc, enable, numFrames, ffRampUpTime, ffRampUpFraction)



#TODO: calibRefToField should be multidimensional
refToField(daq::RedPitayaDAQ, d::Int64) = daq.params.calibRefToField[d]



