

function controlLoop(daq::AbstractDAQ)
  N = daq.params.numSampPerPeriod
  numChannels = numTxChannels(daq)

  setTxParams(daq, daq.params.currTxAmp, daq.params.currTxPhase)
  sleep(daq.params.controlPause)

  controlPhaseDone = false
  while !controlPhaseDone
    period = currentPeriod(daq)
    @time uMeas, uRef = readDataPeriods(daq, 1, period+1)

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
  #c1 = calibIntToVoltRef(daq)
  for d=1:numTxChannels(daq)
    c2 = refToField(daq, d)

    #uVolt = c1[1,d].*float(uRef[:,d,1]) .+ c1[2,d]
    uVolt = float(uRef[1:daq.params.numSampPerPeriod,d,1])

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
    newTxPhase = daq.params.currTxPhase .- phase
    wrapPhase!(newTxPhase)

    newTxAmp = daq.params.currTxAmp .* daq.params.dfStrength ./ amplitude

    println("new tx amplitude=$(newTxAmp)) phase=$(newTxPhase)")

    deviation = abs.( daq.params.currTxAmp ./ amplitude .-
                     daq.params.calibFieldToVolt ) ./ daq.params.calibFieldToVolt

    println("We expected $(daq.params.calibFieldToVolt) and
            got $(daq.params.currTxAmp ./ amplitude), deviation: $deviation")

    if all( newTxAmp .< daq.params.txLimitVolt ) &&
       maximum( deviation ) < 0.2
      daq.params.currTxAmp[:] = newTxAmp
      daq.params.currTxPhase[:] = newTxPhase
    else
      plot(vec(uRef))
      println("Could not control")

      #stopTx(daq)
      #disconnect(daq)
      #startTx(daq)
    end
    setTxParams(daq, daq.params.currTxAmp, daq.params.currTxPhase)

    return false
  end
end
