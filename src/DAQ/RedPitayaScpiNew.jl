export DAQRedPitayaScpiNew, disconnect, setSlowDAC, getSlowADC, connectToServer,
       setTxParamsAll, disconnect

type DAQRedPitayaScpiNew <: AbstractDAQ
  params::DAQParams
  rpc::RedPitayaCluster
end

function DAQRedPitayaScpiNew(params)
  p = DAQParams(params)
  rpc = RedPitayaCluster(params["ip"])
  daq = DAQRedPitayaScpiNew(p, rpc)
  setACQParams(daq)
  if !masterTrigger(daq.rpc)
    ramWriterMode(daq.rpc, "TRIGGERED")
    modeDAC(daq.rpc, "RASTERIZED")

    for d=1:numChan(daq.rpc)
      for e=1:length(daq.params.rpModulus)
        modulusDAC(daq.rpc, d, e, daq.params.rpModulus[e])
      end
    end
    masterTrigger(daq.rpc, true)
  end
  #disconnect(daq)
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
  samplesPerPeriod(daq.rpc, daq.params.numSampPerPeriod * daq.params.acqNumAverages)
  periodsPerFrame(daq.rpc, daq.params.acqNumPeriodsPerFrame)

  #masterTrigger(daq.rpc, false)

  # upload multi-patch LUT TODO!!!
  if length(daq.params.acqFFValues) > 0
    numSlowDACChan(master(daq.rpc), daq.params.acqNumFFChannels)
    if length(daq.params.acqFFValues) == daq.params.acqNumPeriodsPerFrame*daq.params.acqNumFFChannels
      setSlowDACLUT(master(daq.rpc), daq.params.acqFFValues)
    else
      # If numPeriods is larger than the LUT we repeat the values
      setSlowDACLUT(master(daq.rpc), repeat(vec(daq.params.acqFFValues),
            inner=div(daq.params.acqNumPeriodsPerFrame, length(daq.params.acqFFValues))))
    end
  else
    numSlowDACChan(master(daq.rpc), 0)
  end

  return nothing
end

function startTx(daq::DAQRedPitayaScpiNew)
  connect(daq.rpc)
  #connectADC(daq.rpc)
  startADC(daq.rpc)
  #masterTrigger(daq.rpc, true)
  while currentFrame(daq.rpc) < 0
    sleep(0.1)
  end
  return nothing
end


function stopTx(daq::DAQRedPitayaScpiNew)
  setTxParams(daq, zeros(numTxChannels(daq)),
                   zeros(numTxChannels(daq)))
  stopADC(daq.rpc)
  #RedPitayaDAQServer.disconnect(daq.rpc)
end

function disconnect(daq::DAQRedPitayaScpiNew)
  RedPitayaDAQServer.disconnect(daq.rpc)
end

function setSlowDAC(daq::DAQRedPitayaScpiNew, value, channel)

  setSlowDAC(daq.rpc, channel, value)

  return nothing
end

function getSlowADC(daq::DAQRedPitayaScpiNew, channel)
  return getSlowADC(daq.rpc, channel)
end

enableSlowDAC(daq::DAQRedPitayaScpiNew, enable::Bool) = enableSlowDAC(daq.rpc,enable)

function setTxParams(daq::DAQRedPitayaScpiNew, amplitude, phase)
  if any( daq.params.currTxAmp .>= daq.params.txLimitVolt )
    error("This should never happen!!! \n Tx voltage is above the limit")
  end

  for d=1:numTxChannels(daq)
    amp = round(Int, 8192 * amplitude[d])
    ph = phase[d] / 180 * pi #+ pi/2
    e = daq.params.dfChanToModulusIdx[d]
    amplitudeDAC(daq.rpc, daq.params.dfChanIdx[d], e, amp)
    phaseDAC(daq.rpc, daq.params.dfChanIdx[d], e, ph )
    modulusFactorDAC(daq.rpc, daq.params.dfChanIdx[d], e, 1)
  end
  return nothing
end

#=
function setTxParamsAll(daq::DAQRedPitayaScpiNew,d::Integer,
                        amplitude::Vector{Float32},
                        phase::Vector{Float32},
                        modulusFac::Vector{UInt32} = ones(Int,4))

  for e=1:4
    amplitudeDAC(rp, d, 1, e, 8192 * amplitude[e])
    phaseDAC(rp, d, 1, e, phase[e] + pi/2 )
    modulusFactorDAC(rp, d, 1, e, modulusFac[e] )
  end
end
=#

#TODO: calibRefToField should be multidimensional
refToField(daq::DAQRedPitayaScpiNew, d::Int64) = daq.params.calibRefToField[d]


function readData(daq::DAQRedPitayaScpiNew, numFrames, startFrame)
  u = readData(daq.rpc, startFrame, numFrames, daq.params.acqNumAverages)

  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

  uMeas = u[:,daq.params.rxChanIdx,:,:]
  uRef = u[:,daq.params.refChanIdx,:,:]

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
