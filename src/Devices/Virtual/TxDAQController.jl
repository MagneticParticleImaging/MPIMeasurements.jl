export TxDAQControllerParams, TxDAQController, controlTx

Base.@kwdef mutable struct TxDAQControllerParams <: DeviceParams
  phaseAccuracy::Float64
  amplitudeAccuracy::Float64
  controlPause::Float64
  maxControlSteps::Int64 = 20
  correctCrossCoupling::Bool = false
end

Base.@kwdef mutable struct TxDAQController <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TxDAQControllerParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  currTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  desiredTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  sinLUT::Union{Matrix{Float64}, Nothing} = nothing
  cosLUT::Union{Matrix{Float64}, Nothing} = nothing
  controlledChannels::Vector{TxChannelParams} = []
end


function controlTx(txCont::TxDAQController, daq::RedPitayaDAQ, seq::Sequence, initTx::Union{Matrix{ComplexF64}, Nothing} = nothing)
  # Prepare and check channel under control
  controlledChannel = getControlledChannel(seq)
  controlledIds = [id for id in id.(controlledChannel)]
  missingControlDef = []
  txCont.controlledChannels = []
  for id in controlledIds
    chan = get(daq.params.channels, id, nothing)
    if isnothing(chan) || isnothing(chan.feedback) || !in(chan.feedback.channelID, daq.refChanIDs)
      push!(missingControlDef, id)
    else 
      push!(txCont.controlledChannels, chan)
    end
  end
  if length(missingControlDef) > 0
    message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and") * ", but either the channel was not defined or had no defined feedback channel."
    throw(IllegalStateException(message))
  end

  # Check that channels only have one component
  if any(x -> length(x.components) > 1, controlledChannel)
    throw(IllegalStateException("Sequence has channel with more than one component. Such a channel cannot be controlled by this controller"))
  end

  if !isnothing(initTx) 
    s = size(initTx)
    # Not square or does not fit controlled channel matrix
    if !(length(s) == 0 || all(isequal(s[1]), s))
      throw(IllegalStateException("Given initTx for control tx has dimenions $s that is either not square or does not match the amount of controlled channel"))
    end
  end

  # Prepare init and LUT values
  if isnothing(initTx)
    txCont.currTx = convert(Matrix{ComplexF64}, diagm(ustrip.(u"V", [limitPeak(daq, id(channel))/10 for channel in controlled])))
  else 
    txCont.currTx = initTx
  end
  sinLUT, cosLUt = createLUTs(txCont, seq::Sequence)
  txCont.sinLUT = sinLUT
  txCont.cosLUT = cosLUt

  controlPhaseDone = false
  i = 1
  while !controlPhaseDone && i <= txCont.params.maxControlSteps
    @info "CONTROL STEP $i"
    period = currentPeriod(daq)
    uMeas, uRef = readDataPeriods(daq, 1, period + 1)

    controlPhaseDone = doControlStep(txCont, daq, seq, uRef)

    sleep(txCont.params.controlPause)
    i += 1
  end
  stopTx(daq)
  setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
  return txFromMatrix(txCont, txCont.currTx)
end

getControlledChannel(seq::Sequence) = [channel for field in seq.fields if field.control for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel]

function txFromMatrix(txCont::TxDAQController, Γ::Matrix{ComplexF64})
  amplitudes = Dict{String, Vector{Union{Float32, Nothing}}}()
  phases = Dict{String, Vector{Union{Float32, Nothing}}}()
  for (d, channel) in enumerate(txCont.controlledChannels)
    amps = []
    phs = []
    for (e, channel) in enumerate(txCont.controlledChannels)
      push!(amps, abs(Γ[d, e]))
      push!(phs, angle(Γ[d, e]))
    end
    amplitudes[channel] = amps
    phases[channel] = phs
  end
  return amplitudes, phases
end

function createLUTs(txCont::TxDAQController, seq::Sequence)
  N = rxNumSamplingPoints(seq)
  D = length(txCont.controlledChannels)
  dfCycle = ustrip(dfCycle(seq))
  base = ustrip(dfBaseFrequency(seq))
  dfFreq = [base/x.components[1].divider for x in txCont.controlledChannels]
  
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

function doControlStep(txCont::TxDAQController, daq::RedPitayaDAQ, seq::Sequence, uRef)

  Γ = calcFieldFromRef(daq,uRef)
  Ω = calcDesiredField(txCont, daq, seq)

  @info "reference Γ=" Γ

  if controlStepSuccessful(Γ, Ω, daq)
    @info "Could control"
    return true
  else
    newTx = newDFValues(Γ, Ω, daq)
    oldTx = txCont.currTx
    @info "oldTx=" oldTx 
    @info "newTx=" newTx

    if checkDFValues(newTx, oldTx, Γ, daq)
      txCont.currTx[:] = newTx
      setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
    else
      @warn "New values are above voltage limits or are different than expected!"
    end

    @info "Could not control !"
    return false
  end
end

function calcFieldFromRef(txCont::TxDAQController, daq::RedPitayaDAQ, seq::Sequence, uRef)
  len = length(txCont.controlledChannels)
  Γ = zeros(ComplexF64, len, len)

  for d=1:len
    for e=1:len
      c = ustrip(u"mT/V", txCont.controlledChannels[d].feedback.calibration)

      uVolt = float(uRef[1:rxNumSamplingPoints(seq),d,1])

      a = 2*sum(uVolt.*txCont.cosLUT[:,e])
      b = 2*sum(uVolt.*txCont.sinLUT[:,e])

      Γ[d,e] = c*(b+im*a)
    end
  end
  return Γ
end

function calcDesiredField(txCont::TxDAQController, daq::RedPitayaDAQ, seq::Sequence)
  temp = [ustrip(ch.components[1].amplitude[1]) * exp(im*ustrip(ch.components[1].phase[1])) for ch in txCont.controlledChannels]
  return convert(Matrix{ComplexF64}, diagm(temp))
end

function controlStepSuccessful(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

  if txCont.params.correctCrossCoupling
    diff = Ω - Γ
  else
    diff = diagm(diag(Ω)) - diagm(diag(Γ))
  end
  deviation = maximum(abs.(diff)) / maximum(abs.(Ω))
  @info "Ω = " Ω
  @info "Γ = " Γ
  @info "Ω - Γ = " diff
  @info "deviation = $(deviation)   allowed= $(txCOnt.txCont.params.amplitudeAccuracy)"
  return deviation < txCont.params.amplitudeAccuracy
end

function newDFValues(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

  κ = txCont.currTx
  if txCont.params.correctCrossCoupling
    β = Γ*inv(κ)
  else 
    @show size(Γ), size(κ)
    β = diagm(diag(Γ))*inv(diagm(diag(κ))) 
  end
  newTx = inv(β)*Ω

  @warn "here are the values"
  @show κ
  @show Γ
  @show Ω
  

  return newTx
end

function checkDFValues(newTx, oldTx, Γ, txCont::TxDAQController, daq::RedPitayaDAQ)

  calibFieldToVoltEstimate = [ustrip(u"V/mT", daq.params.channels[id(ch)].calibration) for ch in txCont.controlledChannels]
  calibFieldToVoltMeasured = abs.(diag(oldTx) ./ diag(Γ)) 

  deviation = abs.(1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate)

  @info "We expected $(calibFieldToVoltEstimate) and got $(calibFieldToVoltMeasured), deviation: $deviation"

  return all( abs.(newTx) .<  ustrip.(u"V", [limitPeak(daq, id(channel)) for channel in controlled]) ) && maximum( deviation ) < 0.2
end