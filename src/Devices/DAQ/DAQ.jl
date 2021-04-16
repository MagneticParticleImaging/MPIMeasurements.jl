using Graphics: @mustimplement

import Base: setindex!, getindex

export AbstractDAQ, startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels, DAQ, dataConversionFactor,
      readDataPeriod, currentPeriod

@quasiabstract struct AbstractDAQ <: Device end

include("Control.jl")
#include("Plotting.jl")
include("Parameters.jl")

@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, startFrame, numFrames)
@mustimplement readDataPeriods(daq::AbstractDAQ, startPeriod, numPeriods)
@mustimplement refToField(daq::AbstractDAQ, d::Int64)

numTxChannels(daq::AbstractDAQ) = length(daq.params.dfDivider)
numRxChannels(daq::AbstractDAQ) = length(daq.params.rxChanIdx)

function startTxAndControl(daq::AbstractDAQ)
  startTx(daq)
  controlLoop(daq)
end

include("RedPitayaScpiNew.jl")
include("DummyDAQ.jl")

DAQ(params::Dict) = searchDeviceByType(AbstractDAQ, params)

function initLUT(N,D, dfCycle, dfFreq)
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, dfCycle*dfFreq[d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
    end
  end
  return sinLUT, cosLUT
end

function dataConversionFactor(daq::AbstractDAQ) #default
  factor = zeros(2,numRxChannels(daq))
  factor[1,:] = 1.0
  factor[2,:] = 0.0
  return factor
end

function readDataControlled(daq::AbstractDAQ, numFrames)
  controlLoop(daq)
  readData(daq, numFrames, currentFrame(daq))
end

#include("TransferFunction.jl")
