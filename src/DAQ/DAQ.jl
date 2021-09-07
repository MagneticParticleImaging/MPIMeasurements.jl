using Graphics: @mustimplement

import Base: setindex!, getindex

export startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels, DAQ, dataConversionFactor,
      readDataPeriod, currentPeriod

@compat abstract type AbstractDAQ end
abstract type AsyncBuffer end


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

@mustimplement setSequenceParams(daq::AbstractDAQ) # Needs to be able to update seqeuence parameters
@mustimplement prepareSequence(daq::AbstractDAQ) # Sequence can be prepared before started
@mustimplement endSequence(daq::AbstractDAQ) # Sequence can be ended outside of producer
@mustimplement prepareTx(daq::AbstractDAQ; allowControlLoop = true) # Tx can be set outside of producer 
@mustimplement startProducer(channel::Channel, daq::AbstractDAQ, numFrames)
@mustimplement channelType(daq::AbstractDAQ) # What is written to the channel
@mustimplement AsyncBuffer(daq::AbstractDAQ) # Buffer structure that contains channel elements
@mustimplement updateAsyncBuffer!(buffer::AsyncBuffer, chunk) # Adds channel element to buffer
@mustimplement retrieveMeasAndRef!(buffer::AsyncBuffer, daq::AbstractDAQ) # Retrieve all available measurement and reference frames from the buffer

numTxChannels(daq::AbstractDAQ) = length(daq.params.dfDivider)
numRxChannels(daq::AbstractDAQ) = length(daq.params.rxChanIdx)

include("RedPitayaScpiNew.jl")
include("DummyDAQ.jl")

function DAQ(params::Dict)
  if params["daq"] == "RedPitayaScpiNew"
    return DAQRedPitayaScpiNew(params)
  elseif params["daq"] == "DummyDAQ"
    return DummyDAQ(params)
  else
    error("$(params["daq"]) not yet implemented!")
  end
end

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

function asyncProducer(channel::Channel, daq::AbstractDAQ, numFrames; prepTx = true, prepSeq = true, endSeq = true)
  if prepTx
      prepareTx(daq)
  end
  if prepSeq
      setSequenceParams(daq)
      prepareSequence(daq)
  end
  
  endFrame = startProducer(channel, daq, numFrames)

  if endSeq
      endSequence(daq, endFrame)
  end
end

include("TransferFunction.jl")
