function startTxAndControl(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)

  startTx(daq)
  controlLoop(seqCont)
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


function controlLoop(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)

  # for

  # if canConvolute(daq)
  # # Init LUT

  # # Loop over fields
  # #   -> Control and decouple fields
  # if daq.params.controlPhase
  #   controlLoop_(daq)
  # else
  #   tx = daq.params.calibFieldToVolt.*daq.params.dfStrength.*exp.(im*daq.params.dfPhase)
  #   setTxParams(daq, convert(Matrix{ComplexF64}, diagm(tx)), postpone=true)
  # end
  # return
end

function controlLoop_(daq::AbstractDAQ)
  @info "Init control with Tx= " daq.params.currTx
  @info daq.params.correctCrossCoupling

  setTxParams(daq, daq.params.currTx)
  startTx(daq)
  sleep(daq.params.controlPause)

  controlPhaseDone = false
  i = 1
  maxControlSteps = 20
  while !controlPhaseDone && i <= maxControlSteps
    @info "### CONTROL STEP $i ###"
    period = currentPeriod(daq)
    uMeas, uRef = readDataPeriods(daq, 1, period+1)

    controlPhaseDone = doControlStep(daq, uRef)

    sleep(daq.params.controlPause)
    i += 1
  end
  stopTx(daq)
  
  setTxParams(daq, daq.params.currTx) # set value for next true measurement
  return 
end

function calcFieldFromRef(daq::AbstractDAQ, uRef)
  Γ = zeros(ComplexF64, numTxChannels(daq), numTxChannels(daq))
  for d=1:numTxChannels(daq)
    for e=1:numTxChannels(daq)
      c = refToField(daq, d)

      uVolt = float(uRef[1:daq.params.numSampPerPeriod,d,1])

      a = 2*sum(uVolt.*daq.params.cosLUT[:,e])
      b = 2*sum(uVolt.*daq.params.sinLUT[:,e])

      Γ[d,e] = c*(b+im*a)
    end
  end
  return Γ
end

function controlStepSuccessful(Γ::Matrix, Ω::Matrix, daq)

  if daq.params.correctCrossCoupling
    diff = Ω - Γ
  else
    diff = diagm(diag(Ω)) - diagm(diag(Γ))
  end
  deviation = maximum(abs.(diff)) / maximum(abs.(Ω))
  #=@info "Ω = " Ω
  @info "Γ = " Γ
  @info "Ω - Γ = " diff=#
  @info "deviation = $(deviation)   allowed= $(daq.params.controlLoopAmplitudeAccuracy)"

  return deviation < daq.params.controlLoopAmplitudeAccuracy

end

function newDFValues(Γ::Matrix, Ω::Matrix, daq)

  κ = daq.params.currTx
  if daq.params.correctCrossCoupling
    β = Γ*inv(κ)
  else
    @show size(Γ), size(κ)
    β = diagm(diag(Γ))*inv(diagm(diag(κ)))
  end
  newTx = inv(β)*Ω

  #= @warn "here are the values"
  @show κ
  @show Γ
  @show Ω
  =#

  return newTx
end

function checkDFValues(newTx, oldTx, Γ, daq)

  calibFieldToVoltEstimate = daq.params.calibFieldToVolt
  calibFieldToVoltMeasured = abs.(diag(oldTx) ./ diag(Γ))

  deviation = abs.( 1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate )

  @info "We expected $(calibFieldToVoltEstimate) and got $(calibFieldToVoltMeasured), deviation: $deviation"

  return all( abs.(newTx) .< daq.params.txLimitVolt ) && maximum( deviation ) < 0.2
end

function doControlStep(daq::AbstractDAQ, uRef)

  Γ = calcFieldFromRef(daq,uRef)
  Ω = convert(Matrix{ComplexF64}, diagm(daq.params.dfStrength.*exp.(im*daq.params.dfPhase)))

  amplitude = abs.(diag(Γ))

  @info "reference Γ=" Γ

  if controlStepSuccessful(Γ, Ω, daq)
    @info "Could control"
    return true
  else
    newTx = newDFValues(Γ, Ω, daq)
    oldTx = daq.params.currTx
    @info "oldTx=" oldTx
    @info "newTx=" newTx

    if checkDFValues(newTx, oldTx, Γ, daq)
      daq.params.currTx[:] = newTx
      setTxParams(daq, daq.params.currTx)
    else
      @warn "New values are above voltage limits or are different than expected!"
    end

    @info "Could not control !"
    return false
  end
end
