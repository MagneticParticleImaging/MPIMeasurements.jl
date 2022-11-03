export TxDAQControllerParams, TxDAQController, controlTx

Base.@kwdef mutable struct TxDAQControllerParams <: DeviceParams
  phaseAccuracy::Float64
  amplitudeAccuracy::Float64
  controlPause::Float64
  maxControlSteps::Int64 = 20
  fieldToVoltDeviation::Float64 = 0.2
  correctCrossCoupling::Bool = false
end
TxDAQControllerParams(dict::Dict) = params_from_dict(TxDAQControllerParams, dict)

struct SortedRef end
struct UnsortedRef end

struct ControlledChannel
  seqChannel::PeriodicElectricalChannel
  daqChannel::TxChannelParams
end

mutable struct ControlSequence
  targetSequence::Sequence
  currSequence::Sequence
  # Periodic Electric Components
  simpleChannel::OrderedDict{PeriodicElectricalChannel, TxChannelParams}
  sinLUT::Union{Matrix{Float64}, Nothing}
  cosLUT::Union{Matrix{Float64}, Nothing}
  refIndices::Vector{Int64}
  # Arbitrary Waveform
end

Base.@kwdef mutable struct TxDAQController <: VirtualDevice
  @add_device_fields TxDAQControllerParams

  currTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  desiredTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  sinLUT::Union{Matrix{Float64}, Nothing} = nothing
  cosLUT::Union{Matrix{Float64}, Nothing} = nothing
  controlledChannels::Vector{ControlledChannel} = []
end

function _init(tx::TxDAQController)
  # NOP
end

neededDependencies(::TxDAQController) = [AbstractDAQ]
optionalDependencies(::TxDAQController) = [SurveillanceUnit, Amplifier, TemperatureController]

function ControlSequence(txCont::TxDAQController, target::Sequence, daq::AbstractDAQ)
  # Prepare Periodic Electrical Components
  seqControlledChannel = getControlledChannel(txCont, target)
  simpleChannel = createPeriodicElectricalComponentDict(seqControlledChannel, target, daq)
  sinLUT, cosLUT = createLUTs(seqControlledChannel, target)


  currSeq = target
  
  _name = "Control Sequence for target $(name(target))"
  description = ""
  _targetScanner = targetScanner(target)
  _baseFrequency = baseFrequency(target)
  general = GeneralSettings(;name=_name, description = description, targetScanner = _targetScanner, baseFrequency = _baseFrequency)
  # TODO do i need rx channel?
  acq = AcquisitionSettings(;channels = RxChannel[], bandwidth = rxBandwidth(target))

  _fields = MagneticField[]
  for field in fields(target)
    if control(field)
      _id = id(field)
      safeStart = safeStartInterval(field)
      safeTrans = safeTransitionInterval(field)
      safeEnd = safeEndInterval(field)
      safeError = safeErrorInterval(field)
      # Init purely periodic electrical component channel
      periodicChannel = [deepcopy(channel) for channel in periodicElectricalTxChannels(field) if length(arbitraryElectricalComponents(channel)) == 0]
      periodicComponents = [comp for channel in periodicChannel for comp in periodicElectricalComponents(channel)]
      for channel in periodicChannel
        otherComp = filter(!in(periodicElectricalComponents(channel)), periodicComponents)
        for comp in periodicElectricalComponents(channel)
          # TODO smarter init value, maybe min between 1/10 and target (<- target might not be V)
          amplitude!(comp, simpleChannel[channel].limitPeak/10)
        end
        if txCont.params.correctCrossCoupling
          for comp in otherComp
            copy = deepcopy(comp)
            amplitude!(copy, 0.0u"V")
            push!(channel, copy)
          end
        end
      end
      # Init arbitrary waveform
      # TODO Implement AWG
      contField = MagneticField(;id = _id, channels = periodicChannel, safeStartInterval = safeStart, safeTransitionInterval = safeTrans, 
          safeEndInterval = safeEnd, safeErrorInterval = safeError, control = true)
      push!(_fields, contField)
    end
  end

  # Create Ref Indexing
  mapping = Dict( b => a for (a,b) in enumerate(channelIdx(daq, daq.refChanIDs)))
  controlOrderChannelIndices = [channelIdx(daq, ch.feedback.channelID) for ch in Base.values(simpleChannel)]
  refIndices = [mapping[x] for x in controlOrderChannelIndices]


  currSeq = Sequence(;general = general, acquisition = acq, fields = _fields)
  return ControlSequence(target, currSeq, simpleChannel, sinLUT, cosLUT, refIndices)
end

function createPeriodicElectricalComponentDict(seqControlledChannel::Vector{PeriodicElectricalChannel}, seq::Sequence, daq::AbstractDAQ)
  missingControlDef = []
  dict = OrderedDict{PeriodicElectricalChannel, TxChannelParams}()

  for seqChannel in seqControlledChannel
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    #if isnothing(daqChannel) || isnothing(daqChannel.feedback) || !in(daqChannel.feedback.channelID, daq.refChanIDs)
    #  push!(missingControlDef, name)
    #else
      dict[seqChannel] = daqChannel
    #end
  end
  
  #if length(missingControlDef) > 0
  #  message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and") * ", but either the channel was not defined or had no defined feedback channel."
  #  throw(IllegalStateException(message))
  #end

  # Check that we only control three channels, as our RedPitayaDAQs only have 3 signal components atm
  if length(dict) > 3
    throw(IllegalStateException("Sequence requires controlling of more than four channels, which is currently not implemented."))
  end

  # Check that channels only have one component
  if any(x -> length(x.components) > 1, seqControlledChannel)
    throw(IllegalStateException("Sequence has channel with more than one component. Such a channel cannot be controlled by this controller"))
  end
  return dict
end

function controlTx(txCont::TxDAQController, seq::Sequence, ::Nothing = nothing)
  daq = dependency(txCont, AbstractDAQ)
  control = ControlSequence(txCont, seq, daq)
  return controlTx(txCont, seq, control)
end


function controlTx(txCont::TxDAQController, seq::Sequence, control::ControlSequence)
  # Prepare and check channel under control
  daq = dependency(txCont, AbstractDAQ)
  

  Ω = calcDesiredField(control)

  # Start Tx
  su = nothing
  if hasDependency(txCont, SurveillanceUnit)
    su = dependency(txCont, SurveillanceUnit)
  end
  if !isnothing(su)
    enableACPower(su)
  end

  tempControl = nothing
  if hasDependency(txCont, TemperatureController)
    tempControl = dependency(txCont, TemperatureController)
  end
  if !isnothing(tempControl)
    disableControl(tempControl)
  end

  amps = []
  if hasDependency(txCont, Amplifier)
    amps = dependencies(txCont, Amplifier)
  end
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    txChannelIds = id.(vcat(acyclicElectricalTxChannels(seq), periodicElectricalTxChannels(seq)))
    amps = filter(amp -> in(channelId(amp), txChannelIds), amps)
    @sync for amp in amps
      @async turnOn(amp)
    end
  end

  # Hacky solution
  setup(daq, cont.currSequence)
  controlPhaseDone = false
  i = 1
  try
    while !controlPhaseDone && i <= txCont.params.maxControlSteps
      @info "CONTROL STEP $i"
      # Prepare control measurement
      ch = Channel{channelType(daq)}(32)
      buffer = AsyncBuffer(daq)
      @info "Control measurement started"
      producer = @async begin 
        endSample = asyncProducer(channel, daq, cont.currSequence)
        endSequence(daq, endSample)
      end
      bind(ch, producer)
      consumer = @async begin 
        while isopen(channel) || isready(channel)
          while isready(channel)
            chunk = take!(channel)
            updateAsyncBuffer!(buffer, chunk)
          end
          sleep(0.001)
        end      
      end
      wait(consumer)
      @info "Control measurement finished"

      @info "Evaluating control step"
      uMeas, uRef = retrieveMeasAndRef!(buffer, daq)
      if !isnothing(uRef)
        controlPhaseDone = doControlStep(txCont, control, uRef, Ω)
      else
        error("Could not retrieve reference signal")
      end
      i += 1
    end
  catch ex
    @error "Exception during control loop"
    @error ex
  finally
    try 
      stopTx(daq)
    catch ex
      @error "Could not stop tx"
      @error ex
    end
    @sync for amp in amps
      @async try 
        turnOff(amp)
      catch ex
        @error "Could not turn off amplifier $(deviceID(amp))"
        @error ex
      end
    end
    try 
      if !isnothing(tempControl)
        enableControl(tempControl)
      end
    catch ex
      @error "Could not enable heating control"
      @error ex
    end
    try
      if !isnothing(su)
        disableACPower(su)
      end
    catch ex
      @error "Could not disable AC power"
      @error ex
    end
  end
  
  if !controlPhaseDone
    error("TxDAQController $(deviceID(txCont)) could not control.")
  end

  # Prepare Tx for proper measurement
  setupRx(daq, cont.targetSequence)
  setupTx(daq, cont.currSequence)
  return control
end

getControlledChannel(::TxDAQController, seq::Sequence) = [channel for field in seq.fields if field.control for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel && length(arbitraryElectricalComponents(channel)) == 0]
getUncontrolledChannel(::TxDAQController, seq::Sequence) = [channel for field in seq.fields if !field.control for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel]

function createLUTs(seqChannel::Vector{PeriodicElectricalChannel}, seq::Sequence)
  N = rxNumSamplingPoints(seq)
  D = length(seqChannel)
  cycle = ustrip(dfCycle(seq))
  base = ustrip(dfBaseFrequency(seq))
  dfFreq = [base/x.components[1].divider for x in seqChannel]
  
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, cycle*dfFreq[d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
    end
  end
  return sinLUT, cosLUT
end

function doControlStep(txCont::TxDAQController, cont::ControlSequence, uRef, Ω::Matrix)
  Γ = calcFieldFromRef(cont, uRef)
  if checkFieldDeviation(Γ, Ω, txCont)
    @info "Could control"
    return true
  else
    updateControl!(cont, Γ, Ω, txCont)
    @info "Could not control !"
    return false
  end
end

calcFieldFromRef(cont::ControlSequence, uRef) = calcFieldFromRef(cont, uRef, UnsortedRef())
function calcFieldFromRef(cont::ControlSequence, uRef::Array{Any, 4}, ::UnsortedRef)
  return calcFieldFromRef(cont, uRef[:, :, :, 1], UnsortedRef())
end
function calcFieldFromRef(cont::ControlSequence, uRef::Array{Any, 3}, ::UnsortedRef)
  return calcFieldFromRef(cont, uRef[:, cont.refIndices, :], SortedRef())
end

function calcFieldFromRef(cont::ControlSequence, uRef, ::SortedRef)
  len = length(keys(cont.simpleChannel))
  Γ = zeros(ComplexF64, len, len)

  for d=1:len
    c = ustrip(u"T/V", Base.values(cont.simpleChannel)[d].feedback.calibration)
    for e=1:len

      uVolt = float(uRef[1:rxNumSamplingPoints(cont.currSequence),d,1])

      a = 2*sum(uVolt.*txCont.cosLUT[:,e])
      b = 2*sum(uVolt.*txCont.sinLUT[:,e])

      Γ[d,e] = c*(b+im*a)
    end
  end
  return Γ
end

function calcDesiredField(cont::ControlSequence)
  seqChannel = keys(cont.simpleChannel)
  temp = [ustrip(amplitude(components(ch)[1])) * exp(im*ustrip(phase(components(ch)[1]))) for ch in seqChannel]
  return convert(Matrix{ComplexF64}, diagm(temp))
end

#checkFieldDeviation(uRef, cont::ControlSequence, txCont::TxDAQController) = checkFieldDeviation(calcFieldFromRef(cont, uRef), cont, txCont)
checkFieldDeviation(Γ::Matrix, cont::ControlSequence, txCont::TxDAQController) = checkFieldDeviation(Γ, calcDesiredField(cont), txCont)
function checkFieldDeviation(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)
  if txCont.params.correctCrossCoupling
    diff = Ω - Γ
  else
    diff = diagm(diag(Ω)) - diagm(diag(Γ))
  end
  deviation = maximum(abs.(diff)) / maximum(abs.(Ω))
  @debug "Check field deviation" Ω Γ
  @debug "Ω - Γ = " diff
  @info "deviation = $(deviation) allowed= $(txCont.params.amplitudeAccuracy)"
  return deviation < txCont.params.amplitudeAccuracy
end

updateControl!(cont::ControlSequence, uRef, txCont::TxDAQController) = updateControl!(cont, calcFieldFromRef(cont, uRef), calcDesiredField(cont), txCont)
function updateControl!(cont::ControlSequence, Γ::Matrix, Ω::Matrix, txCont::TxDAQController)
  @debug "Updating control values"
  κ = calcControlMatrix(cont)
  newTx = updateControlMatrix(Γ, Ω, κ, correct_coupling = txCont.params.correctCrossCoupling)
  if checkFieldToVolt(κ, Γ, cont, txCont) && checkVoltLimits(newTx, cont, txCont)
    updateControlSequence!(cont, newTx)
  else
    @warn "New control values are not allowed"
  end
end
# Γ: Matrix from Ref
# Ω: Desired Matrix
# κ: Last Set Matrix
function updateControlMatrix(Γ::Matrix, Ω::Matrix, κ::Matrix; correct_coupling::Bool = false)
  if correct_coupling
    β = Γ*inv(κ)
  else 
    β = diagm(diag(Γ))*inv(diagm(diag(κ))) 
  end
  newTx = inv(β)*Ω
  @debug "Last matrix:" κ
  @debug "Ref matrix" Γ
  @debug "Desired matrix" Ω
  @debug "New matrix" newTx 
  return newTx
end

function calcControlMatrix(cont::ControlSequence)
  # TxDAQController only works on one field atm (possible future TODO: update to multiple fields, matrix per field)
  field = fields(cont.currSequence)[1]
  len = length(keys(cont.simpleChannel))
  κ = zeros(ComplexF64, len, len)
  # In each channel the first component is the channels "own" component, the following are the ordered correction components of the other channel
  # -> For Channel 2 its components in the matrix row should be c2 c1 c3 for a 3x3 matrix 
  for (i, channel) in enumerate([channel for channel in periodicElectricalTxChannels(field) if length(arbitraryElectricalComponents(channel)) == 0])
    next = 2
    comps = periodicElectricalComponents(channel)
    for j = 1:len
      comp = nothing
      if (i == j) 
        comp = comps[1]
      elseif next <= length(comps)
        comp = comps[next]
        next+=1
      end

      val = 0.0
      if !isnothing(comp)
        r = ustrip(u"V", amplitude(comp))
        angle = ustrip(u"rad", phase(comp))
        val = r*cos(angle) + r*sin(angle)*im
      end
      κ[i, j] = val
    end
  end
  return κ
end

function updateControlSequence!(cont::ControlSequence, newTx::Matrix)
  # TxDAQController only works on one field atm (possible future TODO: update to multiple fields, matrix per field)
  field = fields(cont.currSequence)[1]
  for (i, channel) in enumerate([channel for channel in periodicElectricalTxChannels(field) if length(arbitraryElectricalComponents(channel)) == 0])
    comps = periodicElectricalComponents(channel)
    j = 1
    for (k, comp) in enumerate(comps)
      val = 0.0
      # First component is a diagonal entry from the matrix
      if length(comps) == 1 || k == i
        val = newTx[i, i]
      # All other components are "in order" and skip the diagonal entry
      else
        if j == i 
          j+=1
        end
        val = newTx[i, j]
        j+=1
      end
      amplitude!(comp, abs(val)*1.0u"V")
      phase!(comp, angle(val)*1.0u"rad")
    end
  end

end

function checkFieldToVolt(oldTx, Γ, cont::ControlSequence, txCont::TxDAQController)
  calibFieldToVoltEstimate = [ustrip(u"V/T", ch.calibration) for ch in Base.values(cont.simpleChannel)]
  calibFieldToVoltMeasured = abs.(diag(oldTx) ./ diag(Γ))
  deviation = abs.(1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate)
  @debug "We expected $(calibFieldToVoltEstimate) and got $(calibFieldToVoltMeasured), deviation: $deviation"
  valid = maximum( deviation ) < txCont.params.fieldToVoltDeviation
  if !valid
    @warn "Measured field to volt deviates by $deviation from estimate, exceeding allowed deviation"
  end
  return valid
end

function checkVoltLimits(newTx, cont::ControlSequence, txCont::TxDAQController)
  validChannel = abs.(newTx) .<  ustrip.(u"V", [channel.limitPeak for channel in Base.values(cont.simpleChannel)])
  if !all(valid)
    @debug "Valid Tx Channel" validChannel
    @warn "New control sequence exceeds voltage limits of tx channel"
  end
end

function close(txCont::TxDAQController)
  # NOP
end