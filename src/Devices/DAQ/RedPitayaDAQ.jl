# import RedPitayaDAQServer: currentFrame, currentPeriod, readData, readDataPeriods,
#                            setSlowDAC, getSlowADC, enableSlowDAC, readDataSlow

export RedPitayaDAQ, disconnect, setSlowDAC, getSlowADC, connectToServer,
       setTxParamsAll, disconnect
using RedPitayaDAQServer #@reexport 

Base.@kwdef struct RedPitayaDAQ <: AbstractDAQ
  params::DAQParams
  rpc::RedPitayaCluster
end

function RedPitayaDAQ(params)
  p = DAQParams(params)
  rpc = RedPitayaCluster(params["ip"])
  daq = RedPitayaDAQ(p, rpc)
  setACQParams(daq)
  masterTrigger(daq.rpc, false)
  triggerMode(daq.rpc, params["triggerMode"])
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "STANDARD")
  masterTrigger(daq.rpc, true)

  daq.params.currTx = convert(Matrix{ComplexF64}, diagm(daq.params.txLimitVolt ./ 10))
  return daq
end

function updateParams!(daq::RedPitayaDAQ, params_::Dict)
  connect(daq.rpc)
  
  daq.params = DAQParams(params_)
  
  setACQParams(daq)
end

currentFrame(daq::RedPitayaDAQ) = currentFrame(daq.rpc)
currentPeriod(daq::RedPitayaDAQ) = currentPeriod(daq.rpc)


function calibIntToVoltRx(daq::RedPitayaDAQ)
  return daq.params.calibIntToVolt[:,daq.params.rxChanIdx]
end

function calibIntToVoltRef(daq::RedPitayaDAQ)
  return daq.params.calibIntToVolt[:,daq.params.refChanIdx]
end

function setACQParams(daq::RedPitayaDAQ)
  decimation(daq.rpc, daq.params.decimation)

  for l=1:(2*length(daq.rpc.rp))
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
  slowDACStepsPerFrame(daq.rpc, div(daq.params.acqNumPeriodsPerFrame,daq.params.acqNumPeriodsPerPatch))
 
  if !isempty(daq.params.acqFFValues) 
    numSlowDACChan(master(daq.rpc), daq.params.acqNumFFChannels)
    setSlowDACLUT(master(daq.rpc), daq.params.acqFFValues.*daq.params.calibFFCurrentToVolt)
    if !isempty(daq.params.acqEnableSequence)
      enableDACLUT(master(daq.rpc), daq.params.acqEnableSequence)
    else # We might want to solve this differently
      enableDACLUT(master(daq.rpc), ones(Bool, length(daq.params.acqFFValues)))
    end
  else
    numSlowDACChan(master(daq.rpc), 0)
  end


  numSlowADCChan(daq.rpc, 4)

  return nothing
end

function startTx(daq::RedPitayaDAQ)
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

function stopTx(daq::RedPitayaDAQ)
  setTxParams(daq, zeros(ComplexF64, numTxChannels(daq),numTxChannels(daq)))
  stopADC(daq.rpc)
  #RedPitayaDAQServer.disconnect(daq.rpc)
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
      # The following is a very worse and dangerous hack. Right now postponing the activation of 
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

#TODO: calibRefToField should be multidimensional
refToField(daq::RedPitayaDAQ, d::Int64) = daq.params.calibRefToField[d]


function readData(daq::RedPitayaDAQ, numFrames, startFrame)
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

function readDataPeriods(daq::RedPitayaDAQ, numPeriods, startPeriod)
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
