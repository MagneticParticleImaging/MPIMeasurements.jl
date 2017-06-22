

function controlLoop(daq::AbstractDAQ)
  N = daq["numSampPerPeriod"]
  numChannels = numTxChannels(daq)

  if !haskey(daq.params,"currTxAmp")
    daq["currTxAmp"] = 0.1*ones(numChannels)
    daq["currTxPhase"] = zeros(numChannels)
  end
  setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])
  sleep(daq["controlPause"])

  controlPhaseDone = false
  while !controlPhaseDone
    @time uMeas, uRef = readData(daq, 1, currentFrame(daq))

    controlPhaseDone = doControlStep(daq, uRef)

    sleep(daq["controlPause"])
  end

end


function doControlStep(daq::AbstractDAQ, uRef)
## TODO make me multidimensional
  a = sum(uRef[:,1,1].*daq["cosLUT"][:,1])
  b = sum(uRef[:,1,1].*daq["sinLUT"][:,1])

  amplitude = sqrt(a*a+b*b)*refToField(daq)[1]
  phase = atan2(a,b) / pi * 180;

  println("reference amplitude=$amplitude phase=$phase")

  if abs(daq["dfStrength"][1] - amplitude)/daq["dfStrength"][1] < 0.01 &&
     abs(phase) < 0.1
    return true
  else
    daq["currTxPhase"] .-= phase
    daq["currTxAmp"] *=  daq["dfStrength"][1] / amplitude

    println("new tx amplitude=$(daq["currTxAmp"])) phase=$(daq["currTxPhase"])")
    setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])
    return false
  end
end
