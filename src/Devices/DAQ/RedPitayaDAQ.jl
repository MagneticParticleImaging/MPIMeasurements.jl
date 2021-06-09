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
  rpc::Union{RedPitayaCluster, Missing} = missing

  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []
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
      scannerChannel = daq.params.channels[channel.id]
      push!(daq.rxChanIDs, channel.id)
      #daq.rxChannelIDMapping[channel.id] = scannerChannel.channelIdx
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
  #RedPitayaDAQServer.disconnect(daq.rpc)
end

function setTxParams(daq::RedPitayaDAQ, Γ; postpone=false)
  if any( abs.(daq.params.currTx) .>= daq.params.txLimitVolt )
    error("This should never happen!!! \n Tx voltage is above the limit")
  end

  for d=1:numTxChannels(daq)
    for e=1:numTxChannels(daq)

      amp = abs(Γ[d,e])
      ph = angle(Γ[d,e])
      phaseDAC(daq.rpc, daq.params.dfChanIdx[d], e, ph )

      #@info "$d $e mapping = $(daq.params.dfChanIdx[d]) $amp   $ph   $(frequencyDAC(daq.rpc, daq.params.dfChanIdx[d], e))"

      #if postpone
      # The following is a very bad and dangerous hack. Right now postponing the activation of 
      # fast Tx channels into the sequence does not work on slave RPs. For this reason we switch it on there
      # directly
      if postpone && daq.params.dfChanIdx[d] <= 2   
        amplitudeDACNext(daq.rpc, daq.params.dfChanIdx[d], e, amp) 
      else
        amplitudeDAC(daq.rpc, daq.params.dfChanIdx[d], e, amp)
      end
    end
  end
  return nothing
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



