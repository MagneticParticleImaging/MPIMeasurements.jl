using Graphics: @mustimplement

import Base: setindex!, getindex

export startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled

abstract AbstractDAQ


@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, channel, startFrame, numPeriods)
@mustimplement refToField(daq::AbstractDAQ)

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

end

function readDataControlled(daq::AbstractDAQ, numFrames)
  controlLoop(daq)
  readData(daq, numFrames, currentFrame(daq))
end

function measurement(daq::AbstractDAQ; params=Dict{String,Any}() )

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

function controlLoop(daq::AbstractDAQ)
  N = daq["numSampPerPeriod"]
  numChannels = daq["rxNumChannels"]
  sinBuff = [sin(2 * pi * k / N)/N for k=0:(N-1)]
  cosBuff = [cos(2 * pi * k / N)/N for k=0:(N-1)]

  if !haskey(daq.params,"currTxAmp")
    daq["currTxAmp"] = 0.1*ones(numChannels)
    daq["currTxPhase"] = zeros(numChannels)
  end
  setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])
  sleep(0.5)

  controlPhaseDone = false
  while !controlPhaseDone
    @time uMeas, uRef = readData(daq, 1, currentFrame(daq))
    a = sum(uRef[:,1,1].*cosBuff)
    b = sum(uRef[:,1,1].*sinBuff)

    amplitude = sqrt(a*a+b*b)*refToField(daq)
    phase = atan2(a,b) / pi * 180;

    println("feedback amplitude=$amplitude phase=$phase")

    if abs(daq["dfStrength"][1] - amplitude)/daq["dfStrength"][1] < 0.01 &&
       abs(phase) < 0.1
      controlPhaseDone  = true
    end

    daq["currTxPhase"] .-= phase
    daq["currTxAmp"] *=  daq["dfStrength"][1] / amplitude

    setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])

    sleep(0.5)
  end

end




# DO NOT USE
export measurementCont
function measurementCont(daq::AbstractDAQ)
  startTx(daq)

  controlLoop(daq)

  try
      while true
        uMeas, uRef = readData(daq,10, currentFrame(daq))
        showDAQData(daq,vec(uMeas))
        sleep(0.01)
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(mps)
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
