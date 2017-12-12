

function controlLoop(daq::AbstractDAQ)
  N = daq.params.numSampPerPeriod
  numChannels = numTxChannels(daq)

  setTxParams(daq, daq.params.currTxAmp, daq.params.currTxPhase)
  sleep(daq.params.controlPause)

  controlPhaseDone = false
  while !controlPhaseDone
    period = currentPeriod(daq)
    @time uMeas, uRef = readDataPeriods(daq, 1, period)

    controlPhaseDone = doControlStep(daq, uRef)

    sleep(daq.params.controlPause)
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
    c1 = calibParams(daq, d)[3:4]
    c2 = refToField(daq, d)

    uVolt = c1[1].*float(uRef[:,d,1]) .+ c1[2]

    a = 2*sum(uVolt.*daq.params.cosLUT[:,d])
    b = 2*sum(uVolt.*daq.params.sinLUT[:,d])

    #println(" $(sqrt(a*a+b*b)) ")

    amplitude[d] = sqrt(a*a+b*b)*c2
    phase[d] = atan2(a,b) / pi * 180
  end
  return amplitude, phase
end

function doControlStep(daq::AbstractDAQ, uRef)

  amplitude, phase = calcFieldFromRef(daq,uRef)

  println("reference amplitude=$amplitude phase=$phase")

  if norm(daq.params.dfStrength - amplitude) / norm(daq.params.dfStrength) <
              daq.params.controlLoopAmplitudeAccuracy &&
     norm(phase) < daq.params.controlLoopPhaseAccuracy
    return true
  else
    daq.params.currTxPhase[:] .-= phase
    wrapPhase!(daq.params.currTxPhase)

    daq.params.currTxAmp[:] .*=  daq.params.dfStrength ./ amplitude

    println("new tx amplitude=$(daq.params.currTxAmp)) phase=$(daq.params.currTxPhase)")
    setTxParams(daq, daq.params.currTxAmp, daq.params.currTxPhase)
    return false
  end
end
