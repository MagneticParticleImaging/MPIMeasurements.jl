

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

function wrapPhase!(phases)
  for d=1:length(phases)
    if phases[d] < -180
      phases[d] += 360
    elseif phases[d] > 180
      phases[d] -= 360
    end
  end
  return phases
end

function calcFieldFromRef(daq::AbstractDAQ, uRef)
  amplitude = zeros(numTxChannels(daq))
  phase = zeros(numTxChannels(daq))
  for d=1:numTxChannels(daq)
    a = 2*sum(float(uRef[:,d,1,1]).*daq["cosLUT"][:,d])
    b = 2*sum(float(uRef[:,d,1,1]).*daq["sinLUT"][:,d])

    #println(" $(sqrt(a*a+b*b)) ")
    amplitude[d] = sqrt(a*a+b*b)*refToField(daq)[1]
    phase[d] = atan2(a,b) / pi * 180
  end
  return amplitude, phase
end

function doControlStep(daq::AbstractDAQ, uRef)

  amplitude, phase = calcFieldFromRef(daq,uRef)

  println("reference amplitude=$amplitude phase=$phase")

  if norm(daq["dfStrength"] - amplitude) / norm(daq["dfStrength"]) <
              daq["controlLoopAmplitudeAccuracy"] &&
     norm(phase) < daq["controlLoopPhaseAccuracy"]
    return true
  else
    daq["currTxPhase"] .-= phase
    wrapPhase!(daq["currTxPhase"])

    daq["currTxAmp"] .*=  daq["dfStrength"] ./ amplitude

    println("new tx amplitude=$(daq["currTxAmp"])) phase=$(daq["currTxPhase"])")
    setTxParams(daq, daq["currTxAmp"], daq["currTxPhase"])
    return false
  end
end
