export DAQRedPitayaScpiNew, disconnect, currentFrame, setSlowDAC, getSlowADC, connectToServer,
       reinit, setTxParamsAll

import Base.write
import PyPlot.disconnect

type DAQRedPitayaScpiNew <: AbstractDAQ
  params::DAQParams
  rpc::RedPitayaCluster
end

function DAQRedPitayaScpiNew(params)
  p = DAQParams(params)
  rpc = RedPitayaCluster(params["ip"])
  connectADC(rpc)
  daq = DAQRedPitayaScpiNew(p, rpc)
  setACQParams(daq)
  return daq
end

function reinit(daq::DAQRedPitayaScpiNew)
  connect(daq.rpc)
  setACQParams(daq)
  return nothing
end

function updateParams!(daq::DAQRedPitayaScpiNew, params_::Dict)
  connect(daq.rpc)
  daq.params = DAQParams(params_)
  setACQParams(daq)
end

numRxChannels(daq::DAQRedPitayaScpiNew) = length(daq.rpc)
currentFrame(daq::DAQRedPitayaScpiNew) = currentFrame(daq.rpc)


export calibParams
function calibParams(daq::DAQRedPitayaScpiNew, d)
  return daq.params.calibIntToVolt[:,d]
  #return reshape(daq.params["calibIntToVolt"],4,:)[:,d]
end

function dataConversionFactor(daq::DAQRedPitayaScpiNew)
  return daq.params.calibIntToVolt[1:2,:]
end

function setACQParams(daq::DAQRedPitayaScpiNew)

  dfAmplitude = daq.params.dfStrength
  dec = daq.params.decimation
  freq = daq.params.dfFreq

  numSampPerAveragedPeriod = daq.params.numSampPerPeriod * daq.params.acqNumAverages

  decimation(daq.rpc, daq.params.decimation)
  samplesPerPeriod(daq.rpc, numSampPerAveragedPeriod)
  periodsPerFrame(daq.rpc, daq.params.acqNumPeriods)

  masterTrigger(daq.rpc, false)
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "RASTERIZED")
  modulus = ones(Int,4)
  modulus[1:length(daq.params.dfDivider)] = daq.params.dfDivider
  for d=1:numTxChannels(daq)
    for e=1:length(daq.params.dfDivider)
      modulusDAC(daq.rpc, d, 1, e, modulus[e])
    end
  end

  # TODO
  #div(length(daq.params.acqFFValues),daq.params.acqNumFFChannels),
  #daq.params.acqNumFFChannels,

  # TODO

  #     if daq.params.acqNumPeriods > 1
  #      write_(daq.sockets[d],map(Float32,daq.params.acqFFValues))
  #    end
  #

  return nothing
end

function startTx(daq::DAQRedPitayaScpiNew)
  connect(daq.rpc)
  startADC(daq.rpc)
  masterTrigger(daq.rpc, true)
  while currentFrame(daq.rpc) < 0
    sleep(0.2)
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

function setSlowDAC(daq::DAQRedPitayaScpiNew, value, channel, d=1)
  #write_(daq.sockets[d],UInt32(4))
  #write_(daq.sockets[d],UInt64(channel))
  #write_(daq.sockets[d],Float32(value))
  setSlowDAC(daq.rpc, d, channel, value)

  return nothing
end

function getSlowADC(daq::DAQRedPitayaScpiNew, channel, d=1)
  #write_(daq.sockets[d],UInt32(5))
  #write_(daq.sockets[d],UInt64(channel))
  return getSlowADC(daq.rpc, d, channel)   #read(daq.sockets[d],Float32)
end

function setTxParams(daq::DAQRedPitayaScpiNew, amplitude, phase)
  for d=1:numTxChannels(daq)
    for e=1:4
      if e==d
        amp = round(Int, 8192 * amplitude[d])
        ph = phase[d] / 180 * pi #+ pi/2
      else
        amp = 0
        ph = 0.0
      end
      amplitudeDAC(daq.rpc, d, 1, e, amp)
      phaseDAC(daq.rpc, d, 1, e, ph )
      modulusFactorDAC(daq.rpc, d, 1, e, 1)
    end
  end
end

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

#TODO: calibRefToField should be multidimensional
refToField(daq::DAQRedPitayaScpiNew, d::Int64) = daq.params.calibRefToField[d]

function readData(daq::DAQRedPitayaScpiNew, numFrames, startFrame)
  dec = daq.params.decimation
  numSampPerPeriod = daq.params.numSampPerPeriod
  numSamp = numSampPerPeriod*numFrames
  numAverages = daq.params.acqNumAverages
  numAllFrames = numAverages*numFrames
  numPeriods = daq.params.acqNumPeriods

  numSampPerFrame = numSampPerPeriod * numPeriods
  numSampPerAveragedPeriod =  numSampPerPeriod * numAverages
  numSampPerAveragedFrame = numSampPerAveragedPeriod * numPeriods

  u = readData(daq.rpc, startFrame, numFrames)

  u_ = reshape(u, 2, numSampPerPeriod, numAverages, numRxChannels(daq),
                     numPeriods, numFrames)

  uAv = mean(u_,3)

  uMeas = uAv[1,:,1,:,:,:] #reshape(uMeas,numSampPerPeriod, numTxChannels(daq),numPeriods,numFrames)
  uRef = uAv[2,:,1,:,:,:] #reshape(uRef, numSampPerPeriod, numTxChannels(daq),numPeriods,numFrames)

  return uMeas, uRef
end
