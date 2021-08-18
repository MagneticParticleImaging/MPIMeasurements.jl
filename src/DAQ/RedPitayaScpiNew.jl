export DAQRedPitayaScpiNew, disconnect, setSlowDAC, getSlowADC, connectToServer,
       setTxParamsAll, disconnect

mutable struct DAQRedPitayaScpiNew <: AbstractDAQ
  params::DAQParams
  rpc::RedPitayaCluster
  acqSeq::Union{AbstractSequence, Nothing}
end

function DAQRedPitayaScpiNew(params)
  p = DAQParams(params)
  rpc = RedPitayaCluster(params["ip"])
  daq = DAQRedPitayaScpiNew(p, rpc, nothing)
  setACQParams(daq)
  masterTrigger(daq.rpc, false)
  triggerMode(daq.rpc, params["triggerMode"])
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "STANDARD")

  daq.params.currTx = convert(Matrix{ComplexF64}, diagm(daq.params.txLimitVolt ./ 10))
  return daq
end

function updateParams!(daq::DAQRedPitayaScpiNew, params_::Dict)
  connect(daq.rpc)
  
  daq.params = DAQParams(params_)
  
  setACQParams(daq)
end

currentFrame(daq::DAQRedPitayaScpiNew) = currentFrame(daq.rpc)
currentPeriod(daq::DAQRedPitayaScpiNew) = currentPeriod(daq.rpc)


function calibIntToVoltRx(daq::DAQRedPitayaScpiNew)
  return daq.params.calibIntToVolt[:,daq.params.rxChanIdx]
end

function calibIntToVoltRef(daq::DAQRedPitayaScpiNew)
  return daq.params.calibIntToVolt[:,daq.params.refChanIdx]
end

function setACQParams(daq::DAQRedPitayaScpiNew)
  decimation(daq.rpc, daq.params.decimation)

  for l=1:(2*length(daq.rpc))
    offsetDAC(daq.rpc, l, daq.params.txOffsetVolt[l])
    #@show offsetDAC(daq.rpc, l)
  end

  for d=1:numTxChannels(daq)
    for e=1:numTxChannels(daq)
      frequencyDAC(daq.rpc, daq.params.dfChanIdx[d], e, daq.params.dfFreq[e]) 
    end   
    signalTypeDAC(daq.rpc, daq.params.dfChanIdx[d], daq.params.dfWaveform)
    jumpSharpnessDAC(daq.rpc, daq.params.dfChanIdx[d], daq.params.jumpSharpness)
  end
  passPDMToFastDAC(daq.rpc, daq.params.passPDMToFastDAC)

  samplesPerPeriod(daq.rpc, daq.params.rxNumSamplingPoints * daq.params.acqNumAverages)

  periodsPerFrame(daq.rpc, daq.params.acqNumPeriodsPerFrame)
  # Previously slowDACStepsPerFrame
  stepsPerRepetition = div(daq.params.acqNumPeriodsPerFrame,daq.params.acqNumPeriodsPerPatch)
  samplesPerSlowDACStep(daq.rpc, div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition))
 
  if !isempty(daq.params.acqFFValues) 
    numSlowDACChan(master(daq.rpc), daq.params.acqNumFFChannels)
    lut = daq.params.acqFFValues.*daq.params.calibFFCurrentToVolt
    enable = nothing
    if !isempty(daq.params.acqEnableSequence)
      enable = daq.params.acqEnableSequence
    end
    daq.acqSeq = ArbitrarySequence(lut, enable, stepsPerRepetition,
    daq.params.acqNumFrames*daq.params.acqNumFrameAverages, daq.params.ffRampUpTime, daq.params.ffRampUpFraction)
    # No enable should be equivalent to just full ones, alternatively implement constant function for enableLUT too
    #else # We might want to solve this differently
    #  enableDACLUT(master(daq.rpc), ones(Bool, length(daq.params.acqFFValues)))
    #end
  else
    numSlowDACChan(master(daq.rpc), 0)
    daq.acqSeq = nothing
  end


  numSlowADCChan(daq.rpc, 4)

  return nothing
end

function startTx(daq::DAQRedPitayaScpiNew)
  connect(daq.rpc)
  #connectADC(daq.rpc)
  masterTrigger(daq.rpc, false)
  startADC(daq.rpc)
  masterTrigger(daq.rpc, true)

  while currentPeriod(daq.rpc) < 1
    sleep(0.001)
  end
  return nothing
end

function stopTx(daq::DAQRedPitayaScpiNew)
  setTxParams(daq, zeros(ComplexF64, numTxChannels(daq),numTxChannels(daq)))
  stopADC(daq.rpc)
  #RedPitayaDAQServer.disconnect(daq.rpc)
end

function disconnect(daq::DAQRedPitayaScpiNew)
  RedPitayaDAQServer.disconnect(daq.rpc)
end

function setSlowDAC(daq::DAQRedPitayaScpiNew, value, channel)

  setSlowDAC(daq.rpc, channel, value.*daq.params.calibFFCurrentToVolt[channel])

  return nothing
end

function getSlowADC(daq::DAQRedPitayaScpiNew, channel)
  return getSlowADC(daq.rpc, channel)
end

function enableSlowDAC(daq::DAQRedPitayaScpiNew) 
  startFrame = 0
  if !isnothing(daq.acqSeq)
    appendSequence(daq.rpc, daq.acqSeq)
    prepareSequence(daq.rpc)
    bandwidth = div(125e6, decimation(daq.rpc))
    period = div(samplesPerSlowDACStep(master(daq.rpc) * slowDACStepsPerSequence(master(daq.rpc))), bandwidth)
    startFrame = ceil(daq.acqSeq.rampTime / period) 
  end
  setTxParams(daq.rpc, )
  
  return startFrame
end

function setTxParams(daq::DAQRedPitayaScpiNew, Γ; postpone=false)
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
      # The following is a very worse and dangerous hack. Right now postponing the activation of 
      # fast Tx channels into the sequence does not work on slave RPs. For this reason we switch it on there
      # directly
      #if postpone && daq.params.dfChanIdx[d] <= 2   
      #  amplitudeDACNext(daq.rpc, daq.params.dfChanIdx[d], e, amp) 
      #else
      amplitudeDAC(daq.rpc, daq.params.dfChanIdx[d], e, amp)
      #end
    end
  end
  return nothing
end

#TODO: calibRefToField should be multidimensional
refToField(daq::DAQRedPitayaScpiNew, d::Int64) = daq.params.calibRefToField[d]

function convertSamplesToFrames(samples, daq::DAQRedPitayaScpiNew)
  unusedSamples = samples
  frames = nothing
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  samplesInBuffer = size(samples)[2]
  framesInBuffer = div(samplesInBuffer, samplesPerFrame)
  if framesInBuffer > 0
      samplesToConvert = view(samples, :, 1:(samplesPerFrame * framesInBuffer))
      frames = convertSamplesToFrames(samplesToConvert, numChan(daq.rpc), samplesPerPeriod(daq.rpc), periodsPerFrame(daq.rpc), framesInBuffer, daq.params.acqNumAverages, 1)
      

      c = daq.params.calibIntToVolt #is calibIntToVolt ever sanity checked?
      for d = 1:size(frames, 2)
        frames[:, d, :, :] .*= c[1,d]
        frames[:, d, :, :] .+= c[2,d]
      end
      
      if (samplesPerFrame * framesInBuffer) + 1 <= samplesInBuffer
          unusedSamples = samples[:, (samplesPerFrame * framesInBuffer) + 1:samplesInBuffer]
      end
  end

  return unusedSamples, frames
end

function startAsyncProducer(daq::DAQRedPitayaScpiNew, channel::Channel, startSample, samplesToRead, chunkSize)
  readPipelinedSamples(daq.rpc, startSample, samplesToRead, channel, chunkSize = chunkSize) # rp info here
end

function convertSamplesToMeasAndRef(samples, daq::DAQRedPitayaScpiNew)
  unusedSamples, frames = convertSamplesToFrames(samples, daq)
  uMeas = nothing
  uRef = nothing
  if !isnothing(frames)
    uMeas = frames[:,daq.params.rxChanIdx,:,:]
    uRef = frames[:,daq.params.refChanIdx,:,:]
  end
  return unusedSamples, uMeas, uRef
end

function readData(daq::DAQRedPitayaScpiNew, numFrames, startFrame)
  u = readData(daq.rpc, startFrame, numFrames, daq.params.acqNumAverages, 1)

  @info "size u in readData: $(size(u))"
  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

  uMeas = u[:,daq.params.rxChanIdx,:,:]
  uRef = u[:,daq.params.refChanIdx,:,:]

  lostSteps = numLostStepsSlowADC(master(daq.rpc))
  if lostSteps > 0
    @error("WE LOST $lostSteps SLOW DAC STEPS!")
  end  

  return uMeas, uRef
end

function readDataPeriods(daq::DAQRedPitayaScpiNew, numPeriods, startPeriod)
  u = readDataPeriods(daq.rpc, startPeriod, numPeriods, daq.params.acqNumAverages)

  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

  uMeas = u[:,daq.params.rxChanIdx,:]
  uRef = u[:,daq.params.refChanIdx,:]

  return uMeas, uRef
end
