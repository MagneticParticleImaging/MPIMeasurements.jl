using Graphics: @mustimplement

import Base: setindex!, getindex

export startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels

abstract AbstractDAQ

include("Control.jl")

@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, channel, startFrame, numPeriods)
@mustimplement refToField(daq::AbstractDAQ)

numRxChannels(daq::AbstractDAQ) = daq["rxNumChannels"]
numTxChannels(daq::AbstractDAQ) = length(daq["dfDivider"])

include("Parameters.jl")
include("RedPitaya.jl")
include("RedPitayaScpi.jl")

getindex(daq::AbstractDAQ, param::String) = daq.params[param]
function setindex!(daq::AbstractDAQ, value, param::String)
  daq.params[param] = value
end

function init(daq::AbstractDAQ)
  daq["dfFreq"] = daq["dfBaseFrequency"] ./ daq["dfDivider"]
  daq["dfPeriod"] = lcm(daq["dfDivider"]) / daq["dfBaseFrequency"]

  daq["numSampPerPeriod"] = round(Int, daq["dfBaseFrequency"] /
                                              daq["decimation"] * daq["dfPeriod"])
  D = numTxChannels(daq)
  N = daq["numSampPerPeriod"]
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, daq["dfPeriod"]*daq["dfFreq"][d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N
    end
  end
  daq["sinLUT"] = sinLUT
  daq["cosLUT"] = cosLUT
end

function readDataControlled(daq::AbstractDAQ, numFrames)
  controlLoop(daq)
  readData(daq, numFrames, currentFrame(daq))
end

function measurement(daq::AbstractDAQ, params=Dict{String,Any}() )

  updateParams(daq, params)

  startTx(daq)
  controlLoop(daq)
  currFr = currentFrame(daq)

  #buffer = zeros(Float32,numSampPerPeriod, numChannels, numFrames)
  #for n=1:numFrames
  #  uMeas = readData(daq, 1, currFr+(n-1)*numAverages, numAverages)
  #    uMeas = mean(uMeas,2)
  #  buffer[:,n] = uMeas
  #end
  uMeas, uRef = readData(daq, daq["acqNumFrames"], currFr)

  stopTx(daq)

  return uMeas
end


# DO NOT USE
export measurementCont
function measurementCont(daq::AbstractDAQ)
  startTx(daq)

  controlLoop(daq)

  try
      while true
        uMeas, uRef = readData(daq,10, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        showAllDAQData(uMeas,1)
        showAllDAQData(uRef,2)
        sleep(0.01)
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(daq)
      else
        rethrow(x)
      end
  end
end





export showDAQData
function showDAQData(u)
  u_ = u
  figure(1)
  clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  semilogy(abs(rfft(u_)),"o-b",lw=2)
  sleep(0.1)
end

function showDAQData(daq,u)
  u_ = u
  figure(1)
  clf()
  subplot(2,1,1)
  plot(u_)
  subplot(2,1,2)
  uhat = abs(rfft(u_))
  freq = (0:(length(uhat)-1)) * daq["dfBaseFrequency"] / daq["dfDivider"][1,1,1]  /10

  semilogy(freq,uhat,"o-b",lw=2)
  sleep(0.1)
end





export showAllDAQData
function showAllDAQData(u, fignum=1)
  D = size(u,2)
  figure(fignum)
  clf()
  for d=1:D
    u_ = vec(u[:,d,:])
    subplot(2,D,(d-1)*2+ 1)
    plot(u_)
    subplot(2,D,(d-1)*2+ 2)
    semilogy(abs(rfft(u_)),"o-b",lw=2)
  end
  sleep(0.1)
end
