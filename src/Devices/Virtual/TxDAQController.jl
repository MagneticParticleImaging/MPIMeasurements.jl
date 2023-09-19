export TxDAQControllerParams, TxDAQController, controlTx

Base.@kwdef mutable struct TxDAQControllerParams <: DeviceParams
  phaseAccuracy::typeof(1.0u"rad")
  relativeAmplitudeAccuracy::Float64
  controlPause::Float64
  absoluteAmplitudeAccuracy::typeof(1.0u"T") = 50.0u"µT"
  maxControlSteps::Int64 = 20
  fieldToVoltDeviation::Float64 = 0.2
  findZeroDC::Bool = false
end
TxDAQControllerParams(dict::Dict) = params_from_dict(TxDAQControllerParams, dict)

struct SortedRef end
struct UnsortedRef end

abstract type ControlSequence end

mutable struct CrossCouplingControlSequence <: ControlSequence
  targetSequence::Sequence
  currSequence::Sequence
  # Periodic Electric Components
  controlledChannelsDict::OrderedDict{PeriodicElectricalChannel, TxChannelParams}
  sinLUT::Union{Matrix{Float64}, Nothing}
  cosLUT::Union{Matrix{Float64}, Nothing}
  refIndices::Vector{Int64}
end

mutable struct AWControlSequence <: ControlSequence
  targetSequence::Sequence
  currSequence::Sequence
  # Periodic Electric Components
  controlledChannelsDict::OrderedDict{PeriodicElectricalChannel, TxChannelParams}
  refIndices::Vector{Int64}
  rfftIndices::BitArray{3} # Matrix of size length(controlledChannelsDict) x 4 (max. num of components) x len(rfft)
  dcCorrection::Union{Vector{Float64}, Nothing}
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

function close(txCont::TxDAQController)
  # NOP
end

neededDependencies(::TxDAQController) = [AbstractDAQ]
optionalDependencies(::TxDAQController) = [SurveillanceUnit, Amplifier, TemperatureController]

function ControlSequence(txCont::TxDAQController, target::Sequence, daq::AbstractDAQ)

  if any(.!isa.(getControlledChannels(target), PeriodicElectricalChannel))
    error("A field that requires control can only have PeriodicElectricalChannels.") # TODO/JA: check if this limitation can be lifted: would require special care when merging a sequence
  end

  currSeq = prepareSequenceForControl(target)
  applyForwardCalibration!(currSeq, daq) # uses the forward calibration to convert the values for the field from T to V

  seqControlledChannels = getControlledChannels(currSeq)

  @debug "ControlSequence" seqControlledChannels
  
  # Dict(PeriodicElectricalChannel => TxChannelParams)
  controlledChannelsDict = createControlledChannelsDict(seqControlledChannels, daq) # should this be changed to components instead of channels?
  refIndices = createReferenceIndexMapping(controlledChannelsDict, daq)
  
  controlSequenceType = decideControlSequenceType(target, txCont.params.findZeroDC)
  @debug "ControlSequence: Decided on using ControlSequence of type $controlSequenceType"

  if controlSequenceType==CrossCouplingControlSequence    
      
    # temporarily remove first (and only) component from each channel
      comps = [popfirst!(channel.components) for channel in periodicElectricalTxChannels(fields(currSeq)[1])]
      
      # insert all components into each channel in the same order, all comps from the other channels are set to 0T
      for (i, channel) in enumerate(periodicElectricalTxChannels(fields(currSeq)[1]))
        for (j, comp) in enumerate(comps)
          copy_ = deepcopy(comp)
          if i!=j        
            amplitude!(copy_, 0.0u"V")
          end
          push!(channel.components, copy_)
        end
      end

    sinLUT, cosLUT = createLUTs(seqControlledChannels, currSeq) # TODO/JA: check if this makes a difference between target and currSeq, though it should not
    
    return CrossCouplingControlSequence(target, currSeq, controlledChannelsDict, sinLUT, cosLUT, refIndices)

  elseif controlSequenceType == AWControlSequence # use the new controller
    
    # AW offset will get ignored -> should be zero
    if any(x->any(mean.(scaledValues.(arbitraryElectricalComponents(x))).>1u"µT"), getControlledChannels(target))
      error("The DC-component of arbitrary waveform components cannot be handled during control! Please remove any DC-offset from your waveform and use the offset parameter of the corresponding channel!")
    end

    rfftIndices = createRFFTindices(controlledChannelsDict, target, daq)

    return AWControlSequence(target, currSeq, controlledChannelsDict, refIndices, rfftIndices, nothing)
  end
end

function decideControlSequenceType(target::Sequence, findZeroDC::Bool=false)

  hasAWComponent = any(isa.([component for channel in getControlledChannels(target) for component in channel.components], ArbitraryElectricalComponent))
  moreThanOneComponent = any(x -> length(x.components) > 1, getControlledChannels(target))
  moreThanThreeChannels = length(getControlledChannels(target)) > 3
  moreThanOneField = length(getControlledFields(target)) > 1
  needsDecoupling_ = needsDecoupling(target)
  @debug "decideControlSequenceType:" hasAWComponent moreThanOneComponent moreThanThreeChannels moreThanOneField needsDecoupling_ findZeroDC

  if needsDecoupling_ && !hasAWComponent && !moreThanOneField && !moreThanThreeChannels && !moreThanOneComponent && findZeroDC
      return CrossCouplingControlSequence
  elseif needsDecoupling_
    throw(SequenceConfigurationError("The given sequence can not be controlled! To control a field with decoupling it cannot have an AW component ($hasAWComponent), more than one field ($moreThanOneField), more than three channels ($moreThanThreeChannels) nor more than one component per channel ($moreThanOneComponent). DC control ($findZeroDC) is also not possible"))
  elseif !hasAWComponent && !moreThanOneField && !moreThanThreeChannels && !moreThanOneComponent && findZeroDC
    return CrossCouplingControlSequence
  else 
    return AWControlSequence 
  end
end

"""
This function creates the correct indices into a channel-wise rfft of the reference channels for each channel in the controlledChannelsDict
"""
function createRFFTindices(controlledChannelsDict::OrderedDict{PeriodicElectricalChannel, TxChannelParams}, seq::Sequence, daq::AbstractDAQ)
  # Goal: create a Vector of index masks for each component
  # N for every single-frequency component that has N periods in the sequence
  # every Mth sample for all arbitraryWaveform components
  numControlledChannels = length(keys(controlledChannelsDict))
  rfftSize = Int(div(rxNumSamplingPoints(seq),2)+1)
  index_mask = falses(numControlledChannels, numComponentsMax(daq)+1, rfftSize)

  refChannelIdx = [channelIdx(daq, ch.feedback.channelID) for ch in collect(Base.values(controlledChannelsDict))]
  

  for (i, channel) in enumerate(keys(controlledChannelsDict))
    for (j, comp) in enumerate(components(channel))
      dfCyclesPerPeriod = Int(lcm(dfDivider(seq))/divider(comp))
      if isa(comp, PeriodicElectricalComponent)
        index_mask[i,j,dfCyclesPerPeriod+1] = true
      elseif isa(comp, ArbitraryElectricalComponent)
        # the frequency samples have a spacing dfCyclesPerPeriod in the spectrum, only use a maximum number of 2^13+1 points, since the waveform has a buffer length of 2^14 (=> rfft 2^13+1)
        N_harmonics = findlast(x->x>1e-8, abs.(rfft(values(comp)/0.5length(values(comp)))))
        index_mask[i,j,dfCyclesPerPeriod+1:dfCyclesPerPeriod:min(rfftSize, N_harmonics*dfCyclesPerPeriod+1)] .= true
        @debug "createRFFTindices: AWG component" divider(comp) sum(index_mask[i,j,:]) N_harmonics
      end
    end
    index_mask[i,end,1] = ~any(index_mask[findall(x->x==refChannelIdx[i], refChannelIdx),end,1]) && channel.dcEnabled # use the first DC enabled channel going to each ref channel to control the DC value with
  end

  # TODO/JA: test if this works
  # Do a or on the mask of all different components
  allComponentMask = .|(eachslice(index_mask, dims=2)...)
  uniqueRefChIdx = unique(refChannelIdx)  
  combinedRefChannelMask = falses(length(uniqueRefChIdx), size(allComponentMask, 2))
  # if two controlled channels are on the same ref channel they should be combined, maybe there is a more elegant way to do this, but I cant figure it out
  for i in 1:numControlledChannels 
    combinedRefChannelMask[findfirst(x->x==refChannelIdx[i], uniqueRefChIdx),:] .|= allComponentMask[i,:]
  end
  # if the total number of trues is smaller than the full array, there is an overlap of different components in the same FFT bin somewhere
  if sum(combinedRefChannelMask) < sum(index_mask)
    throw(SequenceConfigurationError("The controller can not control two different components, that have the same frequency on the same reference channel! This might also include arbitrary waveform components overlapping with normal components in frequency space or multiple TX channels using the same reference channel!"))
  end

  allOffsets = offset.(keys(controlledChannelsDict))
  for refCh in uniqueRefChIdx
    if length(unique(allOffsets[findall(x->x==refCh, refChannelIdx)]))>1
      throw(SequenceConfigurationError("The offsets of all channels going to the same ref channel need to be identical!"))
    end
  end
  
  return index_mask
end

allComponentMask(cont::AWControlSequence) = .|(eachslice(cont.rfftIndices, dims=2)...)

function createLUTs(seqChannel::Vector{PeriodicElectricalChannel}, seq::Sequence)
  N = rxNumSamplingPoints(seq)
  D = length(seqChannel)

  dfCyclesPerPeriod = Int[lcm(dfDivider(seq))/divider(components(chan)[i]) for (i,chan) in enumerate(seqChannel)]

  sinLUT = zeros(D,N)
  cosLUT = zeros(D,N)
  for d=1:D
    for n=1:N
      sinLUT[d,n] = sin(2 * pi * (n-1) * dfCyclesPerPeriod[d] / N)
      cosLUT[d,n] = cos(2 * pi * (n-1) * dfCyclesPerPeriod[d] / N)
    end
  end
  return sinLUT, cosLUT
end

"""
Returns a vector of indices into the the DAQ data after the channels have already been selected by the daq.refChanIDs to select the correct reference channels in the order of the controlledChannels 
"""
function createReferenceIndexMapping(controlledChannelsDict::OrderedDict{PeriodicElectricalChannel, TxChannelParams}, daq::AbstractDAQ)
  # Dict(RedPitaya ChannelIndex => Index in daq.refChanIDs)
  mapping = Dict( b => a for (a,b) in enumerate(channelIdx(daq, daq.refChanIDs)))
  # RedPitaya ChannelIndex der Feedback-Kanäle in Reihenfolge der Kanäle im controlledChannelsDict
  controlOrderChannelIndices = [channelIdx(daq, ch.feedback.channelID) for ch in collect(Base.values(controlledChannelsDict))]
  # Index in daq.refChanIDs in der Reihenfolge der Kanäle im controlledChannelsDict
  return [mapping[x] for x in controlOrderChannelIndices]
end

function prepareSequenceForControl(seq::Sequence)
  # Ausgangslage: Eine Sequenz enthält eine Reihe an Feldern, von denen ggf nicht alle geregelt werden sollen
  # Jedes dieser Felder enthält eine Reihe an Channels, die nicht alle geregelt werden können (nur periodicElectricalChannel)

  # Ziel: Eine Sequenz, die, wenn Sie abgespielt wird, alle Informationen beinhaltet, die benötigt werden, um die Regelung durchzuführen, Sendefelder in V
  
  _name = "Control Sequence for target $(name(seq))"
  description = ""
  _targetScanner = targetScanner(seq)
  _baseFrequency = baseFrequency(seq)
  general = GeneralSettings(;name=_name, description = description, targetScanner = _targetScanner, baseFrequency = _baseFrequency)
  acq = AcquisitionSettings(;channels = RxChannel[], bandwidth = rxBandwidth(seq)) # uses the default values of 1 for numPeriodsPerFrame, numFrames, numAverages, numFrameAverages

  _fields = MagneticField[]
  for field in fields(seq)
    if control(field)
      _id = id(field)
      safeStart = safeStartInterval(field)
      safeTrans = safeTransitionInterval(field)
      safeEnd = safeEndInterval(field)
      safeError = safeErrorInterval(field)
      # Use only periodic electrical channels
      periodicChannel = [deepcopy(channel) for channel in periodicElectricalTxChannels(field)]
      #periodicComponents = [comp for channel in periodicChannel for comp in periodicElectricalComponents(channel)]
      for channel in periodicChannel
        for comp in components(channel)
            if dimension(amplitude(comp)) != dimension(1.0u"T")
              error("The amplitude components of a field that is controlled by a TxDAQController need to be given in T. Please fix component $(id(comp)) of channel $(id(channel))")
            end
        end
      end
      contField = MagneticField(;id = _id, channels = periodicChannel, safeStartInterval = safeStart, safeTransitionInterval = safeTrans, 
          safeEndInterval = safeEnd, safeErrorInterval = safeError, decouple = decouple(field), control = true)
      push!(_fields, contField)
    end
  end
  return Sequence(;general = general, acquisition = acq, fields = _fields)
end


function createControlledChannelsDict(seqControlledChannels::Vector{PeriodicElectricalChannel}, daq::AbstractDAQ)
  missingControlDef = []
  dict = OrderedDict{PeriodicElectricalChannel, TxChannelParams}()

  for seqChannel in seqControlledChannels
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    if isnothing(daqChannel) || isnothing(daqChannel.feedback) || !in(daqChannel.feedback.channelID, daq.refChanIDs)
      @debug "Found missing control def: " name isnothing(daqChannel) isnothing(daqChannel.feedback) !in(daqChannel.feedback.channelID, daq.refChanIDs)
      push!(missingControlDef, name)
    else
      dict[seqChannel] = daqChannel
    end
  end
    
  if length(missingControlDef) > 0
    message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and ") * ", but either the channel was not defined or had no defined feedback channel."
    throw(IllegalStateException(message))
  end

  return dict
end

###############################################################################
############## Top-Level functions for interacting with the controller
###############################################################################

function controlTx(txCont::TxDAQController, seq::Sequence, ::Nothing = nothing)
  if needsControlOrDecoupling(seq)
    daq = dependency(txCont, AbstractDAQ)
    setupRx(daq, seq)
    control = ControlSequence(txCont, seq, daq) # depending on the controlled channels and settings this will select the appropiate type of ControlSequence
    return controlTx(txCont, control)
  else
    @warn "The sequence you selected does not need control, even though the protocol wanted to control!"
    return seq
  end
end

function measureMeanReferenceSignal(daq::AbstractDAQ, seq::Sequence)
  channel = Channel{channelType(daq)}(32)
  buf = AsyncBuffer(SimpleFrameBuffer(1, zeros(Float32,rxNumSamplesPerPeriod(seq),length(daq.rpv)*2,acqNumPeriodsPerFrame(seq),acqNumFrames(seq))), daq)
  @info "DC Control measurement started"
  producer = @async begin
    @debug "Starting DC control producer" 
    endSample = startProducer(channel, daq, 1)
    endSequence(daq, endSample)
  end
  bind(channel, producer)
  consumer = @async begin
    while isopen(channel) || isready(channel)
      while isready(channel)
        chunk = take!(channel)
        push!(buf, chunk)
      end
      sleep(0.001)
    end      
  end
  
  wait(consumer)
  return mean(read(buf.target)[:,channelIdx(daq, daq.refChanIDs),1,1], dims=1)
end

function controlTx(txCont::TxDAQController, control::ControlSequence)
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
    txChannelIds = id.(vcat(acyclicElectricalTxChannels(control.targetSequence), periodicElectricalTxChannels(control.targetSequence)))
    amps = filter(amp -> in(channelId(amp), txChannelIds), amps)
    @sync for amp in amps
      @async turnOn(amp)
    end
  end

  # Hacky solution
  controlPhaseDone = false
  i = 1

  try
    if txCont.params.findZeroDC # this is only possible with AWControlSequence
      # create sequence with every field off, dc set to zero
      # calculate mean for each ref channel
      # create sequence with offsets set to small value
      # measure men for each ref channel again
      # use the two measurements to find the DC value that needs to be output to achieve zero on the reference channel
      # always add found value to DC values in control
      dc_cont = deepcopy(control)
      signals = zeros(ComplexF64,controlMatrixShape(control))
      updateControlSequence!(dc_cont, signals)
      setup(daq, dc_cont.currSequence)
      ref_offsets_0 = measureMeanReferenceSignal(daq, dc_cont.currSequence)[control.refIndices]

      δ = ustrip.(u"V", [1u"mT"*abs(calibration(daq, id(channel))(0)) for channel in getControlledChannels(control)]) # use DC value for offsets
      @debug "findZeroDC: Now outputting the following DC values: [V]" δ
      signals[:,1] .= δ 
      updateControlSequence!(dc_cont, signals)
      setup(daq, dc_cont.currSequence)
      ref_offsets_δ = measureMeanReferenceSignal(daq, dc_cont.currSequence)[control.refIndices]

      dc_correction = -ref_offsets_0./((ref_offsets_δ.-ref_offsets_0)./δ)

      if any(abs.(dc_correction).>maximum(δ)) # We do not accept any change that is larger than what we would expect for 1mT
        error("DC correction too large!")
      end
      @debug "Result of finding Zero DC" ref_offsets_0' ref_offsets_δ' dc_correction' 
      control.dcCorrection = dc_correction
    end

    while !controlPhaseDone && i <= txCont.params.maxControlSteps
      @info "CONTROL STEP $i"
      # Prepare control measurement
      setup(daq, control.currSequence)

      if "checkEachControlStep" in split(ENV["JULIA_DEBUG"],",")
        menu = REPL.TerminalMenus.RadioMenu(["Continue", "Abort"], pagesize=2)
        choice = REPL.TerminalMenus.request("Please confirm the current values for control:", menu)
        if choice == 1
          println("Continuing...")
        else
          println("Control cancelled")
          error("Control cancelled!")
        end
      end

      channel = Channel{channelType(daq)}(32)
      buffer = AsyncBuffer(FrameSplitterBuffer(daq, StorageBuffer[DriveFieldBuffer(1, zeros(ComplexF64, controlMatrixShape(control)..., 1, 1), control)]), daq)
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
      Γ = read(sink(buffer, DriveFieldBuffer))[:, :, 1, 1] # calcFieldsFromRef happened here already
      if !isnothing(Γ)
        controlPhaseDone = controlStep!(control, txCont, Γ, Ω) == UNCHANGED
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

"""
Returns a Sequence that is merged from the control result and all uncontrolled field of the given ControlSequence
"""
function getControlResult(cont::ControlSequence)::Sequence
  
  # Use the magnetic field that are controlled from currSeq and all uncontrolled fields and general settings from target

  _name = "Control Result for target $(name(cont.targetSequence))"
  general = GeneralSettings(;name=_name, description = description(cont.targetSequence), targetScanner = targetScanner(cont.targetSequence), baseFrequency = baseFrequency(cont.targetSequence))
  acq = cont.targetSequence.acquisition

  _fields = MagneticField[]
  for field in fields(cont.currSequence)
      _id = id(field)
      safeStart = safeStartInterval(field)
      safeTrans = safeTransitionInterval(field)
      safeEnd = safeEndInterval(field)
      safeError = safeErrorInterval(field)
      #TODO/JA: should the channels be a copy? Is it even necessary to create a new object just to set control to false? Maybe this will work anyways
      contField = MagneticField(;id = _id, channels = deepcopy(channels(field)), safeStartInterval = safeStart, safeTransitionInterval = safeTrans, 
          safeEndInterval = safeEnd, safeErrorInterval = safeError, decouple = false, control = false)
      push!(_fields, contField)
  end
  for field in fields(cont.targetSequence)
    if !control(field)
      push!(_fields, field)
    end
  end

  return Sequence(;general = general, acquisition = acq, fields = _fields)
end

setup(daq::AbstractDAQ, sequence::ControlSequence) = setup(daq, getControlResult(sequence))


# TODO/JA: check if changes here needs changes somewhere else
getControlledFields(seq::Sequence) = [field for field in seq.fields if field.control]
getControlledChannels(seq::Sequence) = [channel for field in seq.fields if field.control for channel in field.channels]
# The elements of collect(getControlledChannels(cont)) are always identical (===) to getControlledChannels(cont.currSequence)
getControlledChannels(cont::ControlSequence) = keys(cont.controlledChannelsDict) # maybe add collect here as well? for most uses this not needed
getControlledDAQChannels(cont::ControlSequence) = collect(Base.values(cont.controlledChannelsDict))
getPrimaryComponents(cont::CrossCouplingControlSequence) = [components(channel)[i] for (i,channel) in enumerate(getControlledChannels(cont))]

acyclicElectricalTxChannels(cont::ControlSequence) = acyclicElectricalTxChannels(cont.targetSequence)
periodicElectricalTxChannels(cont::ControlSequence) = periodicElectricalTxChannels(cont.targetSequence)
acqNumFrames(cont::ControlSequence) = acqNumFrames(cont.targetSequence)
acqNumFrameAverages(cont::ControlSequence) = acqNumFrameAverages(cont.targetSequence)
acqNumFrames(cont::ControlSequence, x) = acqNumFrames(cont.targetSequence, x)
acqNumFrameAverages(cont::ControlSequence, x) = acqNumFrameAverages(cont.targetSequence, x)
numControlledChannels(cont::ControlSequence) = length(getControlledChannels(cont))

controlMatrixShape(cont::AWControlSequence) = (numControlledChannels(cont), size(cont.rfftIndices,3))
controlMatrixShape(cont::CrossCouplingControlSequence) = (numControlledChannels(cont), numControlledChannels(cont))


#################################################################################
########## Functions for the control steps
#################################################################################



controlStep!(cont::ControlSequence, txCont::TxDAQController, uRef) = controlStep!(cont, txCont, uRef, calcDesiredField(cont))
controlStep!(cont::ControlSequence, txCont::TxDAQController, uRef, Ω::Matrix{<:Complex}) = controlStep!(cont, txCont, calcFieldsFromRef(cont, uRef), Ω)
function controlStep!(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})
  if checkFieldDeviation(cont, txCont, Γ, Ω)
    return UNCHANGED
  elseif updateControl!(cont, txCont, Γ, Ω)
    return UPDATED
  else
    return INVALID
  end
end

#checkFieldDeviation(cont::ControlSequence, txCont::TxDAQController, uRef) = checkFieldDeviation(cont, txCont, calcFieldFromRef(cont, uRef))
checkFieldDeviation(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}) = checkFieldDeviation(cont, txCont, Γ, calcDesiredField(cont))
function checkFieldDeviation(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})

  diff = Ω - Γ
  abs_deviation = abs.(diff)
  rel_deviation = abs_deviation ./ abs.(Ω)
  rel_deviation[abs.(Ω).<1e-15] .= 0 # relative deviation does not make sense for a zero goal
  phase_deviation = angle.(Ω).-angle.(Γ)
  phase_deviation[abs.(Ω).<1e-15] .= 0 # phase deviation does not make sense for a zero goal

  if !needsDecoupling(cont.targetSequence) && !isa(cont,AWControlSequence)
    abs_deviation = diag(abs_deviation)
    rel_deviation = diag(rel_deviation)
    phase_deviation = diag(phase_deviation)
  elseif isa(cont, AWControlSequence)
    abs_deviation = abs_deviation[allComponentMask(cont)]' # TODO/JA: keep the distinction between the channels (maybe as Vector{Vector{}}), instead of putting everything into a long vector with unknown order
    rel_deviation = rel_deviation[allComponentMask(cont)]'
    phase_deviation = phase_deviation[allComponentMask(cont)]'
  end
  @debug "Check field deviation [T]" Ω Γ
  @debug "Ω - Γ = " abs_deviation rel_deviation phase_deviation
  @info "Observed field deviation:\nabs:\t$(abs_deviation*1000) mT\nrel:\t$(rel_deviation*100) %\nφ:\t$(phase_deviation/pi*180)°\n allowed: $(txCont.params.absoluteAmplitudeAccuracy|>u"mT"), $(txCont.params.relativeAmplitudeAccuracy*100) %, $(uconvert(u"°",txCont.params.phaseAccuracy))"
  phase_ok = abs.(phase_deviation) .< ustrip(u"rad", txCont.params.phaseAccuracy)
  amplitude_ok = (abs.(abs_deviation) .< ustrip(u"T", txCont.params.absoluteAmplitudeAccuracy)) .| (abs.(rel_deviation) .< txCont.params.relativeAmplitudeAccuracy)
  @debug "Field deviation:" amplitude_ok phase_ok
  return all(phase_ok) && all(amplitude_ok)
end


updateControl!(cont::ControlSequence, txCont::TxDAQController, uRef) = updateControl!(cont, txCont, calcFieldFromRef(cont, uRef), calcDesiredField(cont))
function updateControl!(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})
  @debug "Updating control values"
  κ = calcControlMatrix(cont)
  newTx = updateControlMatrix(cont, txCont, Γ, Ω, κ)

  if checkFieldToVolt(κ, Γ, cont, txCont, Ω) && checkVoltLimits(newTx, cont)
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
function updateControlMatrix(cont::CrossCouplingControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex}, κ::Matrix{<:Complex})
  if needsDecoupling(cont.targetSequence)
    β = Γ*inv(κ)
  else
    β = diagm(diag(Γ))*inv(diagm(diag(κ))) 
  end
  newTx = inv(β)*Ω
  @debug "Last TX matrix [V]:" κ
  @debug "Ref matrix [T]:" Γ
  @debug "Desired matrix [T]:" Ω
  @debug "New TX matrix [V]:" newTx 
  return newTx
end

function updateControlMatrix(cont::AWControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex}, κ::Matrix{<:Complex})
  # For now we completely ignore coupling and hope that it can find good values anyways
  # The problem is, that to achieve 0 we will always output zero, but we would need a much more sophisticated method to solve this
  newTx = κ./Γ.*Ω

  #@debug "Last TX matrix [V]:" κ=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(κ,cont,return_time_signal=true)')
  #@debug "Ref matrix [T]:" Γ=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(Γ,cont,return_time_signal=true)')
  #@debug "Desired matrix [V]:" Ω=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(Ω,cont,return_time_signal=true)')
  #@debug "New TX matrix [T]:" newTx=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(newTx,cont,return_time_signal=true)')

  return newTx
end

#################################################################################
########## Functions for calculating the field matrix in T from the reference channels
#################################################################################


# calcFieldFromRef(cont::CrossCouplingControlSequence, uRef; frame::Int64 = 1, period::Int64 = 1) = calcFieldFromRef(cont, uRef, UnsortedRef(), frame = frame, period = period)
# function calcFieldFromRef(cont::CrossCouplingControlSequence, uRef::Array{Float32, 4}, ::UnsortedRef; frame::Int64 = 1, period::Int64 = 1)
#   return calcFieldFromRef(cont, uRef[:, :, :, frame], UnsortedRef(), period = period)
# end
# function calcFieldFromRef(cont::CrossCouplingControlSequence, uRef::Array{Float32, 3}, ::UnsortedRef; period::Int64 = 1)
#   return calcFieldFromRef(cont, view(uRef[:, cont.refIndices, :], :, :, period), SortedRef())
# end

function calcFieldsFromRef(cont::CrossCouplingControlSequence, uRef::Array{Float32, 4})
  len = numControlledChannels(cont)
  N = rxNumSamplingPoints(cont.currSequence)
  dividers = divider.(getPrimaryComponents(cont))
  frequencies = ustrip(u"Hz", txBaseFrequency(cont.currSequence))  ./ dividers

  Γ = zeros(ComplexF64, len, len, size(uRef, 3), size(uRef, 4))
  sorted = uRef[:, cont.refIndices, :, :]
  for i = 1:size(Γ, 4)
    for j = 1:size(Γ, 3)
      calcFieldFromRef!(view(Γ, :, :, j, i), cont, view(sorted, :, :, j, i), SortedRef())
    end
  end
  for d =1:len
    c = ustrip(u"T/V", getControlledDAQChannels(cont)[d].feedback.calibration(frequencies[d]))
    for e=1:len
      correction = c * dividers[e]/dividers[d] * 2/N
      for j = 1:size(Γ, 3)
        for i = 1:size(Γ, 4)
          Γ[d, e, j, i] = correction * Γ[d, e, j, i]
        end
      end
    end
  end
  return Γ
end

function calcFieldsFromRef(cont::AWControlSequence, uRef::Array{Float32,4})
  N = rxNumSamplingPoints(cont.currSequence)
  # do rfft channel wise and correct with the transfer function, return as (num control channels x len rfft x periods x frames) Matrix, the selection of [:,:,1,1] is done in controlTx
  spectrum = rfft(uRef, 1)/0.5N
  spectrum[1,:,:,:] ./= 2
  sortedSpectrum = permutedims(spectrum[:, cont.refIndices, :, :], (2,1,3,4))
  frequencies = ustrip.(u"Hz",rfftfreq(N, rxSamplingRate(cont.currSequence)))
  fb_calibration = reduce(vcat, [ustrip.(u"T/V", chan.feedback.calibration(frequencies)) for chan in getControlledDAQChannels(cont)]')
  return sortedSpectrum.*fb_calibration
end

function calcFieldFromRef(cont::CrossCouplingControlSequence, uRef, ::SortedRef)
  len = numControlledChannels(cont)
  N = rxNumSamplingPoints(cont.currSequence)
  dividers = Int64[divider.(getPrimaryComponents(cont))]
  frequencies = ustrip(u"Hz", txBaseFrequency(cont.currSequence)) ./ dividers
  Γ = zeros(ComplexF64, len, len)
  calcFieldFromRef!(Γ, cont, uRef, SortedRef())
  for d =1:len
    c = ustrip(u"T/V", getControlledDAQChannels(cont)[d].feedback.calibration(frequencies[d]))
    for e=1:len
      correction = c * dividers[e]/dividers[d] * 2/N
      Γ[d,e] = correction * Γ[d,e]
    end
  end
  return Γ
end

function calcFieldFromRef!(Γ::AbstractArray{ComplexF64, 2}, cont::CrossCouplingControlSequence, uRef, ::SortedRef)
  len = size(Γ, 1)
  for d=1:len
    for e=1:len
      a = dot(view(uRef, :, d), view(cont.cosLUT, e, :))
      b = dot(view(uRef, :, d), view(cont.sinLUT, e, :))
      Γ[d,e] = (b+im*a)
    end
  end
  return Γ
end


#################################################################################
########## Functions for creating and applying the matrix representation
########## of the controller to the sequence(s)
#################################################################################


# Convert Target Sequence to Matrix in T

function calcDesiredField(cont::CrossCouplingControlSequence)
  desiredField = zeros(ComplexF64, controlMatrixShape(cont))
  for (i, channel) in enumerate(getControlledChannels(cont.targetSequence))
    comp = components(channel)[1]
    desiredField[i, i] = ustrip(u"T", amplitude(comp)) * exp(im*ustrip(u"rad", phase(comp)))
  end
  return desiredField
end

function calcDesiredField(cont::AWControlSequence)
  # generate desired spectrum per control channel that can be compared to the result of calcFieldsFromRef in the controlStep later
  # size: (rfft of sequence x num control channels)
  # the separation of individual components is done by the index masks

  desiredField = zeros(ComplexF64, controlMatrixShape(cont))

  for (i, channel) in enumerate(getControlledChannels(cont.targetSequence))
    
    if cont.rfftIndices[i,end,1]
      desiredField[1,i] = ustrip(u"T", offset(channel))
    end

    for (j, comp) in enumerate(components(channel))
      if isa(comp, PeriodicElectricalComponent)
        if ustrip(u"T",amplitude(comp)) == 0
          @warn "You tried to control a field to 0 T, this will just output 0 V on that channel, since this controller can not correct cross coupling"
        end
        desiredField[i, cont.rfftIndices[i,j,:]] .= ustrip(u"T",amplitude(comp)) * exp(im*ustrip(u"rad",phase(comp)-pi/2)) # The phase given in the component is for a sine, but the FFT-phase uses a cosine
      elseif isa(comp, ArbitraryElectricalComponent)
        desiredField[i, cont.rfftIndices[i,j,:]] .= rfft(ustrip.(u"T",scaledValues(comp)))[2:sum(cont.rfftIndices[i,j,:])+1]/(0.5*2^14) # the buffer length should always be 2^14 currently
      end
    end
  end
  
  return desiredField
end

# Convert Last Tx (currSequence) to Matrix in V
function calcControlMatrix(cont::CrossCouplingControlSequence)
  κ = zeros(ComplexF64, controlMatrixShape(cont))
  for (i, channel) in enumerate(getControlledChannels(cont))
    for (j, comp) in enumerate(periodicElectricalComponents(channel))
      κ[i, j] = ustrip(u"V", amplitude(comp)) * exp(im*ustrip(u"rad", phase(comp)))
    end
  end
  return κ
end

function calcControlMatrix(cont::AWControlSequence)
  oldTx = zeros(ComplexF64, controlMatrixShape(cont))
  for (i, channel) in enumerate(getControlledChannels(cont))
    if cont.rfftIndices[i,end,1]
      oldTx[i,1] = ustrip(u"V", offset(channel))
    end
    for (j, comp) in enumerate(components(channel))
      if isa(comp, PeriodicElectricalComponent)
        oldTx[i, cont.rfftIndices[i,j,:]] .= ustrip(u"V",amplitude(comp)) * exp(im*ustrip(u"rad",phase(comp)-pi/2)) # The phase given in the component is for a sine, but the FFT-phase uses a cosine
      elseif isa(comp, ArbitraryElectricalComponent)
        oldTx[i, cont.rfftIndices[i,j,:]] .= rfft(ustrip.(u"V",scaledValues(comp)))[2:sum(cont.rfftIndices[i,j,:])+1]/(0.5*2^14) # the buffer length should always be 2^14 currently
      end
    end
  end
  return oldTx
end


# Convert New Tx from matrix in V to currSequence
function updateControlSequence!(cont::CrossCouplingControlSequence, newTx::Matrix)
  for (i, channel) in enumerate(periodicElectricalTxChannels(cont.currSequence))
    for (j, comp) in enumerate(components(channel))
      amplitude!(comp, abs(newTx[i, j])*1.0u"V")
      phase!(comp, angle(newTx[i, j])*1.0u"rad")
    end
  end
end

function updateControlSequence!(cont::AWControlSequence, newTx::Matrix)
  for (i, channel) in enumerate(periodicElectricalTxChannels(cont.currSequence))
    if cont.rfftIndices[i,end,1]
      if !isnothing(cont.dcCorrection)
        offset!(channel, (cont.dcCorrection[i]+real(newTx[i,1]))*1.0u"V")
      else
        offset!(channel, real(newTx[i,1])*1.0u"V")
      end
    end
    for (j, comp) in enumerate(components(channel))
      if isa(comp, PeriodicElectricalComponent)
        amplitude!(comp, abs.(newTx[i, cont.rfftIndices[i,j,:]])[]*1.0u"V")
        phase!(comp, angle.(newTx[i, cont.rfftIndices[i,j,:]])[]*1.0u"rad"+(pi/2)u"rad")
      elseif isa(comp, ArbitraryElectricalComponent)
        spectrum = zeros(ComplexF64, 2^13+1)
        spectrum[2:sum(cont.rfftIndices[i,j,:])+1] .= newTx[i, cont.rfftIndices[i,j,:]]
        amplitude!(comp, 1.0u"V")
        phase!(comp, 0.0u"rad")
        values!(comp, irfft(spectrum, 2^14)*(0.5*2^14))
      end
    end
  end
end

#################################################################################
########## Functions for checking the matrix representation for safety and plausibility
#################################################################################



function checkFieldToVolt(oldTx::Matrix{<:Complex}, Γ::Matrix{<:Complex}, cont::CrossCouplingControlSequence, txCont::TxDAQController, Ω::Matrix{<:Complex})
  dividers = divider.(getPrimaryComponents(cont))
  frequencies = ustrip(u"Hz", txBaseFrequency(cont.currSequence))  ./ dividers
  calibFieldToVoltEstimate = [ustrip(u"V/T", chan.calibration(frequencies[i])) for (i,chan) in enumerate(getControlledDAQChannels(cont))]
  calibFieldToVoltMeasured = (diag(oldTx) ./ diag(Γ))

  abs_deviation = abs.(1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate)
  phase_deviation = angle.(calibFieldToVoltMeasured./calibFieldToVoltEstimate)
  @debug "checkFieldToVolt: We expected $(calibFieldToVoltEstimate) V/T and got $(calibFieldToVoltMeasured) V/T, deviation: $(abs_deviation*100) %"
  valid = maximum( abs_deviation ) < txCont.params.fieldToVoltDeviation
  
  if !valid
    @warn "Measured field to volt deviates by $(abs_deviation*100) % from estimate, exceeding allowed deviation of $(txCont.params.fieldToVoltDeviation*100) %"
  elseif maximum(abs.(phase_deviation)) > 10/180*pi
    @warn "The phase of the measured field to volt deviates by $phase_deviation from estimate. Please check you phases! Continuing anyways..."
  end
  return valid
end

function checkFieldToVolt(oldTx::Matrix{<:Complex}, Γ::Matrix{<:Complex}, cont::AWControlSequence, txCont::TxDAQController, Ω::Matrix{<:Complex})
  N = rxNumSamplingPoints(cont.currSequence)
  frequencies = ustrip.(u"Hz",rfftfreq(N, rxSamplingRate(cont.currSequence)))
  calibFieldToVoltEstimate = reduce(vcat,[ustrip.(u"V/T", chan.calibration(frequencies)) for chan in getControlledDAQChannels(cont)]')
  calibFieldToVoltMeasured = oldTx ./ Γ

  mask = allComponentMask(cont) .& (abs.(Ω).>1e-15)
  abs_deviation = abs.(1.0 .- abs.(calibFieldToVoltMeasured[mask])./abs.(calibFieldToVoltEstimate[mask]))
  phase_deviation = angle.(calibFieldToVoltMeasured[mask]) .- angle.(calibFieldToVoltEstimate[mask])
  @debug "checkFieldToVolt: We expected $(calibFieldToVoltEstimate[mask]) V/T and got $(calibFieldToVoltMeasured[mask]) V/T, deviation: $abs_deviation"
  valid = maximum( abs_deviation ) < txCont.params.fieldToVoltDeviation
  if !valid
    @warn "Measured field to volt deviates by $(abs_deviation*100) % from estimate, exceeding allowed deviation of $(txCont.params.fieldToVoltDeviation*100) %"
  elseif maximum(abs.(phase_deviation)) > 10/180*pi
    @warn "The phase of the measured field to volt deviates by $phase_deviation from estimate. Please check you phases! Continuing anyways..."
  end
  return valid
end


function checkVoltLimits(newTx::Matrix{<:Complex}, cont::CrossCouplingControlSequence)
  validChannel = zeros(Bool, size(newTx, 1))
  for i = 1:size(newTx, 1)
    max = sum(abs.(newTx[i, :]))
    validChannel[i] = max < ustrip(u"V", getControlledDAQChannels(cont)[i].limitPeak)
  end
  valid = all(validChannel)
  if !valid
    @debug "Valid Tx Channel" validChannel
    @warn "New control sequence exceeds voltage limits of tx channel"
  end
  return valid
end

function checkVoltLimits(newTx::Matrix{<:Complex}, cont::AWControlSequence; return_time_signal=false)
  validChannel = zeros(Bool, numControlledChannels(cont))
  N = rxNumSamplingPoints(cont.currSequence)

  testSignalTime = irfft(newTx, N, 2)*0.5N

  if return_time_signal
    return testSignalTime
  else
    validChannel = maximum(abs.(testSignalTime), dims=2) .< ustrip.(u"V", getproperty.(getControlledDAQChannels(cont),:limitPeak))
  
    valid = all(validChannel)
    if !valid
      @debug "Valid Tx Channel" validChannel
      @warn "New control sequence exceeds voltage limits of tx channel"
    end
    return valid
  end
end
