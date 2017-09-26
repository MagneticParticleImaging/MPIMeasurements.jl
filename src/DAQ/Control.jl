

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
    frame = currentFrame(daq)
    @time uMeas, uRef = readData(daq, 1, frame)

    controlPhaseDone = doControlStep(daq, uRef)

    sleep(daq["controlPause"])
  end

end


function calcFieldFromRef(daq::AbstractDAQ, uRef)
  a = 2*sum(float(uRef[:,1,1]).*daq["cosLUT"][:,1])
  b = 2*sum(float(uRef[:,1,1]).*daq["sinLUT"][:,1])

  println(" $(sqrt(a*a+b*b)) ")
  amplitude = sqrt(a*a+b*b)*refToField(daq)[1]
  phase = atan2(a,b) / pi * 180
  return amplitude, phase
end

function doControlStep(daq::AbstractDAQ, uRef)
## TODO make me multidimensional

  amplitude, phase = calcFieldFromRef(daq,uRef)

  println("reference amplitude=$amplitude phase=$phase")

  if abs(daq["dfStrength"][1] - amplitude)/daq["dfStrength"][1] <
              daq["controlLoopAmplitudeAccuracy"] &&
     abs(phase) < daq["controlLoopPhaseAccuracy"]
    return true
  else
    daq["currTxPhase"] .-= phase
    if daq["currTxPhase"][1] < -180
      daq["currTxPhase"] .+= 360
    elseif daq["currTxPhase"][1] > 180
      daq["currTxPhase"] .-= 360
    end
    daq["currTxAmp"] *=  daq["dfStrength"][1] / amplitude

    println("new tx amplitude=$(daq["currTxAmp"])) phase=$(daq["currTxPhase"])")
    setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])
    return false
  end
end
