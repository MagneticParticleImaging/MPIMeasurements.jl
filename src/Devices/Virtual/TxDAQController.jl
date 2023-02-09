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

@enum ControlResult UNCHANGED UPDATED INVALID

Base.@kwdef mutable struct TxDAQController <: VirtualDevice
  @add_device_fields TxDAQControllerParams

  ref::Union{Array{Float32, 4}, Nothing} = nothing # TODO remove when done
  cont::Union{Nothing, ControlSequence} = nothing # TODO remove when done
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
  controlOrderChannelIndices = [channelIdx(daq, ch.feedback.channelID) for ch in collect(Base.values(simpleChannel))]
  refIndices = [mapping[x] for x in controlOrderChannelIndices]


  currSeq = Sequence(;general = general, acquisition = acq, fields = _fields)
  return ControlSequence(target, currSeq, simpleChannel, sinLUT, cosLUT, refIndices)
end

acyclicElectricalTxChannels(cont::ControlSequence) = acyclicElectricalTxChannels(cont.targetSequence)
periodicElectricalTxChannels(cont::ControlSequence) = periodicElectricalTxChannels(cont.targetSequence)
acqNumFrames(cont::ControlSequence) = acqNumFrames(cont.targetSequence)
acqNumFrameAverages(cont::ControlSequence) = acqNumFrameAverages(cont.targetSequence)
acqNumFrames(cont::ControlSequence, x) = acqNumFrames(cont.targetSequence, x)
acqNumFrameAverages(cont::ControlSequence, x) = acqNumFrameAverages(cont.targetSequence, x)


function createPeriodicElectricalComponentDict(seqControlledChannel::Vector{PeriodicElectricalChannel}, seq::Sequence, daq::AbstractDAQ)
  missingControlDef = []
  dict = OrderedDict{PeriodicElectricalChannel, TxChannelParams}()

  for seqChannel in seqControlledChannel
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    if isnothing(daqChannel) || isnothing(daqChannel.feedback) || !in(daqChannel.feedback.channelID, daq.refChanIDs)
      push!(missingControlDef, name)
    else
      dict[seqChannel] = daqChannel
    end
  end
  
  if length(missingControlDef) > 0
    message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and ") * ", but either the channel was not defined or had no defined feedback channel."
    throw(IllegalStateException(message))
  end

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
  setupRx(daq, seq)
  control = ControlSequence(txCont, seq, daq)
  return controlTx(txCont, seq, control)
end


function controlTx(txCont::TxDAQController, seq::Sequence, control::ControlSequence)
  # Prepare and check channel under control
  daq = dependency(txCont, AbstractDAQ)
  

  Ω = calcDesiredField(control)
  txCont.cont = control

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
  controlPhaseDone = false
  i = 1
  len = length(keys(control.simpleChannel))
  try
    while !controlPhaseDone && i <= txCont.params.maxControlSteps
      @info "CONTROL STEP $i"
      # Prepare control measurement
      setup(daq, control.currSequence)
      channel = Channel{channelType(daq)}(32)
      buffer = AsyncBuffer(FrameSplitterBuffer(daq, StorageBuffer[DriveFieldBuffer(1, zeros(ComplexF64,len, len, 1, 1), control)]), daq)
      @info "Control measurement started"
      producer = @async begin
        @debug "Starting control producer" 
        endSample = asyncProducer(channel, daq, control.currSequence)
        endSequence(daq, endSample)
      end
      bind(channel, producer)
      consumer = @async begin 
        while isopen(channel) || isready(channel)
          while isready(channel)
            chunk = take!(channel)
            push!(buffer, chunk)
          end
          sleep(0.001)
        end      
      end
      wait(consumer)
      @info "Control measurement finished"

      @info "Evaluating control step"
      uRef = read(sink(buffer, DriveFieldBuffer))[:, :, 1, 1]
      if !isnothing(uRef)
        controlPhaseDone = controlStep!(control, txCont, uRef, Ω) == UNCHANGED
        if controlPhaseDone
          @info "Could control"
        else
          @info "Could not control"
        end
      else
        error("Could not retrieve reference signal")
      end
      i += 1
    end
  catch ex
    @error "Exception during control loop" exception=(ex, catch_backtrace())
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

  return control
end


function setup(daq::RedPitayaDAQ, sequence::ControlSequence)
  stopTx(daq)
  setupRx(daq, sequence.targetSequence)
  setupTx(daq, sequence.currSequence)
  prepareTx(daq, sequence.currSequence)
  setSequenceParams(daq, sequence.targetSequence)
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
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N)
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N)
    end
  end
  return sinLUT, cosLUT
end

controlStep!(cont::ControlSequence, txCont::TxDAQController, uRef) = controlStep!(cont, txCont, uRef, calcDesiredField(cont))
controlStep!(cont::ControlSequence, txCont::TxDAQController, uRef, Ω::Matrix) = controlStep!(cont, txCont, calcFieldFromRef(cont, uRef), Ω)
function controlStep!(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix, Ω::Matrix)
  if checkFieldDeviation(Γ, Ω, txCont)
    return UNCHANGED
  elseif updateControl!(cont, txCont, Γ, Ω)
    return UPDATED
  else
    return INVALID
  end
end

calcFieldFromRef(cont::ControlSequence, uRef; frame::Int64 = 1, period::Int64 = 1) = calcFieldFromRef(cont, uRef, UnsortedRef(), frame = frame, period = period)
function calcFieldFromRef(cont::ControlSequence, uRef::Array{Float32, 4}, ::UnsortedRef; frame::Int64 = 1, period::Int64 = 1)
  return calcFieldFromRef(cont, uRef[:, :, :, frame], UnsortedRef(), period = period)
end
function calcFieldFromRef(cont::ControlSequence, uRef::Array{Float32, 3}, ::UnsortedRef; period::Int64 = 1)
  return calcFieldFromRef(cont, view(uRef[:, cont.refIndices, :], :, :, period), SortedRef())
end

function calcFieldsFromRef(cont::ControlSequence, uRef::Array{Float32, 4})
  len = length(keys(cont.simpleChannel))
  Γ = zeros(ComplexF64, len, len, size(uRef, 3), size(uRef, 4))
  sorted = uRef[:, cont.refIndices, :, :]
  for i = 1:size(Γ, 4)
    for j = 1:size(Γ, 3)
      Γ[:, :, j, i] = calcFieldFromRef(cont, view(sorted, :, :, j, i), SortedRef())
    end
  end
  return Γ
end

function calcFieldFromRef(cont::ControlSequence, uRef, ::SortedRef)
  len = length(keys(cont.simpleChannel))
  N = rxNumSamplingPoints(cont.currSequence)
  Γ = zeros(ComplexF64, len, len)
  dividers = Int64[divider(components(channel)[1]) for channel in keys(cont.simpleChannel)]

  for d=1:len
    c = ustrip(u"T/V", collect(Base.values(cont.simpleChannel))[d].feedback.calibration)
    for e=1:len
      
      a = 0
      b = 0
      for i = 1:N
        a+=uRef[i,d]*cont.cosLUT[i, e]
        b+=uRef[i,d]*cont.sinLUT[i, e]
      end
      a*=2/N
      b*=2/N
      # TODO *im and *(-1) depending on waveform (im for sin instead of cos, -1 as we see the derivative of the field)
      correction = -im * dividers[d]/dividers[e]
      Γ[d,e] = correction * (c*(b+im*a))
    end
  end
  return Γ
end

function calcDesiredField(cont::ControlSequence)
  seqChannel = keys(cont.simpleChannel)
  temp = [ustrip(amplitude(components(ch)[1])) * exp(im*ustrip(phase(components(ch)[1]))) for ch in seqChannel]
  return convert(Matrix{ComplexF64}, diagm(temp))
end

checkFieldDeviation(uRef, cont::ControlSequence, txCont::TxDAQController) = checkFieldDeviation(calcFieldFromRef(cont, uRef), cont, txCont)
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

updateControl!(cont::ControlSequence, txCont::TxDAQController, uRef) = updateControl!(cont, txCont, calcFieldFromRef(cont, uRef), calcDesiredField(cont))
function updateControl!(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix, Ω::Matrix)
  @debug "Updating control values"
  κ = calcControlMatrix(cont)
  newTx = updateControlMatrix(Γ, Ω, κ, correct_coupling = txCont.params.correctCrossCoupling)
  if checkFieldToVolt(κ, Γ, cont, txCont) && checkVoltLimits(newTx, cont, txCont)
    updateControlSequence!(cont, newTx)
    return true
  else
    @warn "New control values are not allowed"
    return false
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
      if k == 1
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
  calibFieldToVoltEstimate = [ustrip(u"V/T", ch.calibration) for ch in collect(Base.values(cont.simpleChannel))]
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
  validChannel = abs.(newTx) .<  ustrip.(u"V", [channel.limitPeak for channel in collect(Base.values(cont.simpleChannel))])
  valid = all(validChannel)
  if !valid
    @debug "Valid Tx Channel" validChannel
    @warn "New control sequence exceeds voltage limits of tx channel"
  end
  return valid
end

function close(txCont::TxDAQController)
  # NOP
end