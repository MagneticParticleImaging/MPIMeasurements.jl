using Graphics: @mustimplement

import Base: setindex!, getindex

export startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels, DAQ, dataConversionFactor

@compat abstract type AbstractDAQ end

include("Control.jl")
include("Plotting.jl")
include("Parameters.jl")

@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, channel, startFrame, numPeriods)
@mustimplement refToField(daq::AbstractDAQ, d::Int64)

@mustimplement numRxChannels(daq::AbstractDAQ)
numTxChannels(daq::AbstractDAQ) = length(daq.params.dfDivider)

#include("RedPitaya.jl")
include("RedPitayaNew.jl")
#include("RedPitayaScpi.jl")
include("Measurements.jl")

function DAQ(params::Dict)
  #=if params["daq"] == "RedPitaya"
    return DAQRedPitaya(params)
  elseif params["daq"] == "RedPitayaScpi"
    return DAQRedPitayaScpi(params)=#
  if params["daq"] == "RedPitayaNew"
    return DAQRedPitayaNew(params)
  else
    error("$(params["daq"]) not yet implemented!")
  end
end

function initLUT(N,D, dfPeriod, dfFreq)
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, dfPeriod*dfFreq[d] )
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

include("TransferFunction.jl")
