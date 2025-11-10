export TxDAQControllerParams, TxDAQController, controlTx

"""
Parameters for a `TxDAQController``

$FIELDS
"""
Base.@kwdef mutable struct TxDAQControllerParams <: DeviceParams
  "Angle, required, allowed deviation of the excitation phase"
  phaseAccuracy::typeof(1.0u"rad")
  "Number, required, allowed relative deviation of the excitation amplitude"
  relativeAmplitudeAccuracy::Float64
  "Magnetic field, default: 50µT, allowed absolute deviation of the excitation amplitude"
  absoluteAmplitudeAccuracy::typeof(1.0u"T") = 50.0u"µT"
  "Integer, default: 20, maximum number of steps to try to control the system"
  maxControlSteps::Int64 = 20
  "Bool, default: false, control the DC value of the excitation field (only posible for DC enabled DF amplifiers)"
  controlDC::Bool = false
  "Float, default: 0.0, time in seconds to wait before the DF is stable after ramping"
  timeUntilStable::Float64 = 0.0
  "Float, default: 0.002, time in seconds that the DF should be averaged during the control measurement"
  minimumStepDuration::Float64 = 0.002
  "Float, default: 0.2, relative deviation allowed between forward calibration and actual system state"
  fieldToVoltRelDeviation::Float64 = 0.2
  "Magnetic field, default: 5.0mT, absolute deviation allowed between forward calibration and actual system state"
  fieldToVoltAbsDeviation::typeof(1.0u"T") = 5.0u"mT"
  "Magnetic field, default: 40mT, maximum field amplitude that the controller should allow"
  maxField::typeof(1.0u"T") = 40.0u"mT"
end
TxDAQControllerParams(dict::Dict) = params_from_dict(TxDAQControllerParams, dict)

struct SortedRef end
struct UnsortedRef end

abstract type ControlSequence end

macro ControlSequence_fields()
  return esc(quote 
  #"Goal sequence of the controller, amplitudes are in T"
  targetSequence::Sequence
  #"Current best guess of a sequence to reach the goal, amplitudes are in V"
  currSequence::Sequence
  #"Dictionary containing the sequence channels needing control and their respective DAQ channels"
  controlledChannelsDict::OrderedDict{PeriodicElectricalChannel, TxChannelParams}
  #"Vector of indices into the receive channels selecting the correct feedback channels for the controlledChannels"
  refIndices::Vector{Int64}
  #"Vector of TransferFunctions to be applied to the feedback channels"
  refTFs::Vector{TransferFunction}
  end)
end

mutable struct CrossCouplingControlSequence <: ControlSequence
  @ControlSequence_fields
  sinLUT::Union{Matrix{Float64}, Nothing}
  cosLUT::Union{Matrix{Float64}, Nothing}
end

mutable struct AWControlSequence <: ControlSequence
  @ControlSequence_fields
  rfftIndices::BitArray{3} # Matrix of size length(controlledChannelsDict) x 4 (max. num of components) x len(rfft)
  dcSearch::Vector{@NamedTuple{V::Vector{Float64}, B::Vector{Float64}}}
  maxIndex::Int
  cachedTFs::Array{ComplexF64,2}
  #lutMap::Dict{String, Dict{AcyclicElectricalTxChannel, Int}} # for every field ID contain a dict of removed LUTChannels together with the corresponding channel
end

@enum ControlResult UNCHANGED UPDATED INVALID

Base.@kwdef mutable struct TxDAQController <: VirtualDevice
  @add_device_fields TxDAQControllerParams

  ref::Union{Array{Float32, 4}, Nothing} = nothing
  cont::Union{Nothing, ControlSequence} = nothing
  startFrame::Int64 = 1
  controlResults::OrderedDict{String, Union{typeof(1.0im*u"V/T"), Dict{Float64,typeof(1.0im*u"V/T")}}} = Dict{String, Union{typeof(1.0im*u"V/T"), Dict{Float64,typeof(1.0im*u"V/T")}}}()
  lastDCResults::Union{Vector{@NamedTuple{V::Vector{Float64}, B::Vector{Float64}}},Nothing} = nothing
  lastChannelIDs::Vector{String} = String[]
end

function calibration(txCont::TxDAQController, channelID::AbstractString)
  if haskey(txCont.controlResults, channelID) && txCont.controlResults[channelID] isa typeof(1.0u"V/T")
    return txCont.controlResults[channelID]
  else
    return calibration(dependency(txCont, AbstractDAQ), channelID)
  end
end

function calibration(txCont::TxDAQController, channelID::AbstractString, frequency::Real)
  frequency = round(frequency,digits=3)
  if haskey(txCont.controlResults, channelID) && txCont.controlResults[channelID] isa Dict && haskey(txCont.controlResults[channelID],frequency)
    return txCont.controlResults[channelID][frequency]
  else
    return calibration(dependency(txCont, AbstractDAQ), channelID, frequency)
  end
end

function _init(tx::TxDAQController)
  # NOP
end

function close(txCont::TxDAQController)
  # NOP
end

neededDependencies(::TxDAQController) = [AbstractDAQ]
optionalDependencies(::TxDAQController) = [SurveillanceUnit, Amplifier, TemperatureController]

function checkIfControlPossible(txCont::TxDAQController, target::Sequence)
  daq = dependency(txCont, AbstractDAQ)

  if any(.!isa.(getControlledChannels(target), ElectricalTxChannel))
    error("A field that requires control can only have ElectricalTxChannels.")
  end

  if !all(unitIsTesla.(getControlledChannels(target)))
    error("All values corresponding to a field that should be controlled need to be given in T, instead of V or A!")
  end

  periodicChannels = [channel for channel in getControlledChannels(target) if typeof(channel) <: PeriodicElectricalChannel]
  lutChannels = [channel for channel in getControlledChannels(target) if typeof(channel) <: AcyclicElectricalTxChannel]

  if !isempty(lutChannels) #&& !txCont.params.controlDC
    error("A field that requires control can only have PeriodicElectricalChannels if controlDC is set to false for the TxDAQController!")
  end

  outputsPeriodic = channelIdx(daq, id.(periodicChannels))
  if !allunique(outputsPeriodic)
    error("Multiple periodic field channels are output on the same DAC output. This can not be controlled!")
  end

  mapToFastDAC(i) = begin x = mod(i,6); if x==1 || x==2; return 2*(i÷6)+x end end
  outputsLUT = channelIdx(daq, id.(lutChannels))
  if !all([x ∈ outputsPeriodic for x = mapToFastDAC.(outputsLUT)])
    error("If AcyclicElectricalTxChannels should be controlled they must map to the same output as a controlled PeriodicElectricalChannel!")
  end


end

function ControlSequence(txCont::TxDAQController, target::Sequence)
  daq = dependency(txCont, AbstractDAQ)
  
  currSeq = prepareSequenceForControl(txCont, target)

  measuredFrames = max(cld(txCont.params.minimumStepDuration, ustrip(u"s", dfCycle(currSeq))),1)
  discardedFrames = cld(txCont.params.timeUntilStable, ustrip(u"s", dfCycle(currSeq)))
  txCont.startFrame = discardedFrames + 1
  acqNumFrames(currSeq, discardedFrames+measuredFrames)
 
  applyForwardCalibration!(currSeq, txCont) # uses the forward calibration to convert the values for the field from T to V

  seqControlledChannels = getControlledChannels(currSeq)

  @debug "ControlSequence" seqControlledChannels
  
  # Dict(PeriodicElectricalChannel => TxChannelParams)
  controlledChannelsDict = createControlledChannelsDict(seqControlledChannels, daq) # should this be changed to components instead of channels?
  refIndices, refTFs = createReferenceIndexMapping(controlledChannelsDict, daq)
  
  controlSequenceType = decideControlSequenceType(target, txCont.params.controlDC)
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
    
    return CrossCouplingControlSequence(target, currSeq, controlledChannelsDict, refIndices, refTFs, sinLUT, cosLUT)

  elseif controlSequenceType == AWControlSequence # use the new controller
    
    # AW offset will get ignored -> should be zero
    if any(x->any(mean.(scaledValues.(arbitraryElectricalComponents(x))).>10u"µT"), getControlledChannels(target))
      error("The DC-component of arbitrary waveform components cannot be handled during control! Please remove any DC-offset from your waveform and use the offset parameter of the corresponding channel!")
    end

    rfftIndices = createRFFTindices(controlledChannelsDict, target, daq)
    if size(rfftIndices,3)>100000
      maxIndex = min(round(Int,max(findlast(.|(eachslice(rfftIndices, dims=(1,2))...))*1.1,65537)),size(rfftIndices,3))
      if iseven(maxIndex); maxIndex+=1 end
    else
      maxIndex = size(rfftIndices,3)
    end
    
    N = rxNumSamplingPoints(currSeq)
    frequencies = ustrip.(u"Hz",rfftfreq(N, rxSamplingRate(currSeq)))
    fbTF = reduce(vcat, transpose([ustrip.(u"V/T", tf(frequencies)) for tf in refTFs]))

    cont = AWControlSequence(target, currSeq, controlledChannelsDict, refIndices, refTFs, rfftIndices, [], maxIndex, fbTF)

    ## Apply last DC result
    if !isnothing(txCont.lastDCResults) && (txCont.lastChannelIDs == id.(seqControlledChannels))
      cont.dcSearch = txCont.lastDCResults[end-1:end]
      Ω = calcDesiredField(cont)
      initTx = calcControlMatrix(cont)
      last = cont.dcSearch[end]
      previous = cont.dcSearch[end-1]
      initTx[:,1] .= previous.V .- ((previous.B.-Ω[:,1]).*(last.V.-previous.V))./(last.B.-previous.B)
      @info "Would have reused last DC Results" initTx[:,1]
      #updateControlSequence!(cont, initTx)
    end

    return cont
  end
end

function decideControlSequenceType(target::Sequence, controlDC::Bool=false)

  hasAWComponent = any(isa.([component for channel in getControlledChannels(target) for component in channel.components], ArbitraryElectricalComponent))
  moreThanOneComponent = any(x -> length(x.components) > 1, getControlledChannels(target))
  moreThanThreeChannels = length(getControlledChannels(target)) > 3
  moreThanOneField = length(getControlledFields(target)) > 1
  needsDecoupling_ = needsDecoupling(target)
  @debug "decideControlSequenceType:" hasAWComponent moreThanOneComponent moreThanThreeChannels moreThanOneField needsDecoupling_ controlDC

  if needsDecoupling_ && !hasAWComponent && !moreThanOneField && !moreThanThreeChannels && !moreThanOneComponent && !controlDC
      return CrossCouplingControlSequence
  elseif needsDecoupling_
    throw(SequenceConfigurationError("The given sequence can not be controlled! To control a field with decoupling it cannot have an AW component ($hasAWComponent), more than one field ($moreThanOneField), more than three channels ($moreThanThreeChannels) nor more than one component per channel ($moreThanOneComponent). DC control ($controlDC) is also not possible"))
  elseif !hasAWComponent && !moreThanOneField && !moreThanThreeChannels && !moreThanOneComponent && !controlDC
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

  refChannelIdx = [channelIdx(daq, ch.feedbackChannelID) for ch in collect(Base.values(controlledChannelsDict))]
  

  for (i, channel) in enumerate(keys(controlledChannelsDict))
    for (j, comp) in enumerate(components(channel))
      dfCyclesPerPeriod = Int(dfSamplesPerCycle(seq)/divider(comp))
      if isa(comp, PeriodicElectricalComponent)
        index_mask[i,j,dfCyclesPerPeriod+1] = true
      elseif isa(comp, ArbitraryElectricalComponent)
        # the frequency samples have a spacing dfCyclesPerPeriod in the spectrum, only use a maximum number of 2^13+1 points, since the waveform has a buffer length of 2^14 (=> rfft 2^13+1)
        N_harmonics = findlast(x->x>1e-8, abs.(rfft(values(comp)/0.5length(values(comp)))))
        index_mask[i,j,dfCyclesPerPeriod+1:dfCyclesPerPeriod:min(rfftSize, N_harmonics*dfCyclesPerPeriod)] .= true
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

  dfCyclesPerPeriod = Int[dfSamplesPerCycle(seq)/divider(components(chan)[i]) for (i,chan) in enumerate(seqChannel)]

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
  controlOrderChannelIndices = [channelIdx(daq, ch.feedbackChannelID) for ch in collect(Base.values(controlledChannelsDict))]
  # Index in daq.refChanIDs in der Reihenfolge der Kanäle im controlledChannelsDict
  refIndices = [mapping[x] for x in controlOrderChannelIndices]
  # Feedback TransferFunction for the controlled Channels
  refTFs = [feedbackTransferFunction(daq, ch) for ch in collect(Base.values(controlledChannelsDict))]
  return refIndices, refTFs
end

function prepareSequenceForControl(txCont::TxDAQController, seq::Sequence)
  # Ausgangslage: Eine Sequenz enthält eine Reihe an Feldern, von denen ggf nicht alle geregelt werden sollen
  # Jedes dieser Felder enthält eine Reihe an Channels, die nicht alle geregelt werden können (nur periodicElectricalChannel)

  # Ziel: Eine Sequenz, die, wenn Sie abgespielt wird, alle Informationen beinhaltet, die benötigt werden, um die Regelung durchzuführen, Sendefelder in V
  checkIfControlPossible(txCont, seq)

  _name = "Control Sequence for target $(name(seq))"
  description = ""
  _targetScanner = targetScanner(seq)
  _baseFrequency = baseFrequency(seq)
  general = GeneralSettings(;name=_name, description = description, targetScanner = _targetScanner, baseFrequency = _baseFrequency)
  acq = AcquisitionSettings(;channels = RxChannel[], bandwidth = rxBandwidth(seq)) # uses the default values of 1 for numPeriodsPerFrame, numFrames, numAverages, numFrameAverages
  
  return Sequence(;general = general, acquisition = acq, fields = [deepcopy(f) for f in fields(seq) if control(f)])
end


function createControlledChannelsDict(seqControlledChannels::Vector{PeriodicElectricalChannel}, daq::AbstractDAQ)
  missingControlDef = []
  dict = OrderedDict{PeriodicElectricalChannel, TxChannelParams}()

  for seqChannel in seqControlledChannels
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    if isnothing(daqChannel) || isnothing(daqChannel.feedbackChannelID) || !in(daqChannel.feedbackChannelID, daq.refChanIDs)
      @debug "Found missing control def: " name isnothing(daqChannel) isnothing(daqChannel.feedbackChannelID) !in(daqChannel.feedbackChannelID, daq.refChanIDs)
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

function controlTx(txCont::TxDAQController, seq::Sequence)
  if needsControlOrDecoupling(seq)
    daq = dependency(txCont, AbstractDAQ)
    setupRx(daq, seq)
    control = ControlSequence(txCont, seq) # depending on the controlled channels and settings this will select the appropiate type of ControlSequence
    return controlTx(txCont, control)
  else
    @warn "The sequence you selected does not need control, even though the protocol wanted to control!"
    return seq
  end
end

function controlTx(txCont::TxDAQController, control::ControlSequence)
  # Prepare and check channel under control
  daq = dependency(txCont, AbstractDAQ)
  
  Ω = calcDesiredField(control)
  txCont.cont = control
  if !checkVoltLimits(calcControlMatrix(control), control)
    error("Initial guess for the controller already exceeds the possibilities of the DAQ!")
  end

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

  amps = getRequiredAmplifiers(txCont, control.currSequence)
  turnOn(amps)

  # Hacky solution
  controlPhaseDone = false
  controlPhaseError = nothing
  i = 1

  try

    while !controlPhaseDone && i <= txCont.params.maxControlSteps
      @info "CONTROL STEP $i"
      # Prepare control measurement
      setup(daq, control.currSequence)

      if haskey(ENV, "JULIA_DEBUG") && contains(ENV["JULIA_DEBUG"],"checkEachControlStep")
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
      buffer = AsyncBuffer(FrameSplitterBuffer(daq, StorageBuffer[DriveFieldBuffer(1, zeros(ComplexF64, controlMatrixShape(control)..., 1, acqNumFrames(control.currSequence)), control)]), daq)
      @debug "Control measurement started"
      producer = @async begin
        @debug "Starting control producer" 
        endSample = asyncProducer(channel, daq, control.currSequence, isControlStep=true)
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
      @debug "Control measurement finished"

      @debug "Evaluating control step"
      tmp = read(sink(buffer, DriveFieldBuffer))
      @debug "Size of calc fields from ref" size(tmp)
      
      Γ = mean(tmp[:, :, 1, txCont.startFrame:end],dims=3)[:,:,1] # calcFieldsFromRef happened here already
      if !isnothing(Γ)
        controlPhaseDone = controlStep!(control, txCont, Γ, Ω) == UNCHANGED
        if controlPhaseDone
          @info "Could control"
          updateCachedCalibration(txCont, control)
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
    resetCachedCalibration(txCont)
    controlPhaseError = ex
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
    if isnothing(controlPhaseError)
      error("TxDAQController $(deviceID(txCont)) could not reach a stable field after $(txCont.params.maxControlSteps) steps.")
    else
      error("TxDAQController $(deviceID(txCont)) failed control with the following message:\n$(sprint(showerror, controlPhaseError))")
    end
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
      contField = MagneticField(;id = _id, channels = deepcopy(channels(field)), safeStartInterval = safeStart, safeTransitionInterval = safeTrans, 
          safeEndInterval = safeEnd, safeErrorInterval = safeError, decouple = false, control = false)
      push!(_fields, contField)
  end
  for field in fields(cont.targetSequence)
    if !control(field)
      push!(_fields, field)
      # TODO/JA: if there are LUT channels sharing a channel with the controlled fields, we should be able to use the DC calibration that has been found
      # and insert it into the corresponding LUT channels as a calibration value
    end
  end

  return Sequence(;general = general, acquisition = acq, fields = _fields)
end

setup(daq::AbstractDAQ, sequence::ControlSequence) = setup(daq, getControlResult(sequence))

function updateCachedCalibration(txCont::TxDAQController, cont::ControlSequence)
  finalCalibration = diag(calcControlMatrix(cont) ./ calcDesiredField(cont))
  channelIds = id.(getControlledChannels(cont))
  dividers = divider.(MPIMeasurements.getPrimaryComponents(cont))
  frequencies = round.(ustrip(u"Hz", txBaseFrequency(cont.currSequence))  ./ dividers, digits=3)
  for i in axes(finalCalibration, 1)
      if !isnan(finalCalibration[i])
        if !haskey(txCont.controlResults, channelIds[i])
          txCont.controlResults[channelIds[i]] = Dict{Float64,typeof(1.0im*u"V/T")}()
        end
        txCont.controlResults[channelIds[i]][frequencies[i]] = finalCalibration[i]*u"V/T"
        @debug "Cached control result: $(round(finalCalibration[i], digits=2)*u"V/T") for channel $(channelIds[i]) at $(round(frequencies[i],digits=3)) Hz" maxlog=10
      end
  end
  
  nothing
end

function updateCachedCalibration(txCont::TxDAQController, cont::AWControlSequence)
  finalCalibration = calcControlMatrix(cont) ./ calcDesiredField(cont)
 
  calibrationResults = findall(x->!isnan(x), finalCalibration)
  channelIDs = id.(getControlledChannels(cont))
  freqAxis = rfftfreq(rxNumSamplingPoints(cont.currSequence),ustrip(u"Hz",2*rxBandwidth(cont.currSequence)))
    
  for res in calibrationResults
    chId = channelIDs[res[1]]
    f = round(freqAxis[res[2]],digits=3)
    if !haskey(txCont.controlResults, chId)
      txCont.controlResults[chId] = Dict{Float64,typeof(1.0im*u"V/T")}()
    end
    if !isnan(finalCalibration[res]) && !iszero(finalCalibration[res])
      txCont.controlResults[chId][f] = finalCalibration[res]*u"V/T"
      @debug "Cached control result:" chId f finalCalibration[res] maxlog=10
    end
  end

  if length(cont.dcSearch) >= 2
    txCont.lastDCResults = cont.dcSearch[end-1:end]
  else
    txCont.lastDCResults = nothing
  end
  txCont.lastChannelIDs = channelIDs
  
  @debug "Cached DC result" txCont.lastDCResults
end

function resetCachedCalibration(txCont::TxDAQController)
  txCont.controlResults = Dict{String, Union{typeof(1.0im*u"V/T"), Dict{Float64,typeof(1.0im*u"V/T")}}}()
  txCont.lastDCResults = nothing
  txCont.lastChannelIDs = String[]
  @debug "Reset cached calibration"
  nothing
end


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
  if fieldAccuracyReached(cont, txCont, Γ, Ω)
    return UNCHANGED
  elseif updateControl!(cont, txCont, Γ, Ω)
    return UPDATED
  else
    return INVALID
  end
end

#fieldAccuracyReached(cont::ControlSequence, txCont::TxDAQController, uRef) = fieldAccuracyReached(cont, txCont, calcFieldFromRef(cont, uRef))
fieldAccuracyReached(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}) = fieldAccuracyReached(cont, txCont, Γ, calcDesiredField(cont))
function fieldAccuracyReached(cont::CrossCouplingControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})

  abs_deviation = abs.(Ω) .- abs.(Γ)
  rel_deviation = abs_deviation ./ abs.(Ω)
  rel_deviation[abs.(Ω).<1e-15] .= 0 # relative deviation does not make sense for a zero goal
  phase_deviation = angle.(Ω).-angle.(Γ)
  phase_deviation[abs.(Ω).<1e-15] .= 0 # phase deviation does not make sense for a zero goal

  if !needsDecoupling(cont.targetSequence)
    abs_deviation = diag(abs_deviation)
    rel_deviation = diag(rel_deviation)
    phase_deviation = diag(phase_deviation)
  # elseif isa(cont, AWControlSequence)
  #   abs_deviation = abs_deviation[allComponentMask(cont)]' # TODO/JA: keep the distinction between the channels (maybe as Vector{Vector{}}), instead of putting everything into a long vector with unknown order
  #   rel_deviation = rel_deviation[allComponentMask(cont)]'
  #   phase_deviation = phase_deviation[allComponentMask(cont)]'
  #   Γt = checkVoltLimits(Γ,cont,return_time_signal=true)'
  #   Ωt = checkVoltLimits(Ω,cont,return_time_signal=true)'

  #   diff = (Ωt .- Γt)
  #   @debug "fieldAccuracyReached" diff=lineplot(1:rxNumSamplingPoints(cont.currSequence),diff, canvas=DotCanvas, border=:ascii)
  #   @info "fieldAccuracyReached2" max_diff = maximum(abs.(diff))
  end
  @debug "Check field deviation [T]" Ω Γ
  @debug "Ω - Γ = " abs_deviation rel_deviation phase_deviation
  @info "Observed field deviation:\nabs:\t$(abs_deviation*1000) mT\nrel:\t$(rel_deviation*100) %\nphi:\t$(phase_deviation/pi*180)°\n allowed: $(txCont.params.absoluteAmplitudeAccuracy|>u"mT"), $(txCont.params.relativeAmplitudeAccuracy*100) %, $(uconvert(u"°",txCont.params.phaseAccuracy))"
  phase_ok = abs.(phase_deviation) .< ustrip(u"rad", txCont.params.phaseAccuracy)
  amplitude_ok = (abs.(abs_deviation) .< ustrip(u"T", txCont.params.absoluteAmplitudeAccuracy)) .| (abs.(rel_deviation) .< txCont.params.relativeAmplitudeAccuracy)
  @debug "Field deviation:" amplitude_ok phase_ok
  return all(phase_ok) && all(amplitude_ok)
end

function fieldAccuracyReached(cont::AWControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})
  
  Γt = transpose(checkVoltLimits(Γ,cont,return_time_signal=true))
  Ωt = transpose(checkVoltLimits(Ω,cont,return_time_signal=true))
  @debug "fieldAccuracyReached" transpose(Γ[allComponentMask(cont)]) abs.(Γ[allComponentMask(cont)])' angle.(Γ[allComponentMask(cont)])'# abs.(Ω[allComponentMask(cont)])' angle.(Ω[allComponentMask(cont)])'
  diff = (Ωt .- Γt)
  zero_mean_diff = diff .- mean(diff, dims=1)
  @debug "fieldAccuracyReached" diff=lineplot(1:size(diff,1),diff*1000, canvas=DotCanvas, border=:ascii, ylabel="mT", name=dependency(txCont, AbstractDAQ).refChanIDs[cont.refIndices])
  @info "Observed field deviation (time-domain):\nmax_diff:\t$(maximum(abs.(diff))*1000) mT\nmax_diff (w/o DC): \t$(maximum(abs.(zero_mean_diff))*1000)"
  amplitude_ok = abs.(diff).< ustrip(u"T", txCont.params.absoluteAmplitudeAccuracy)
  return all(amplitude_ok)
end


#updateControl!(cont::ControlSequence, txCont::TxDAQController, uRef) = updateControl!(cont, txCont, calcFieldFromRef(cont, uRef), calcDesiredField(cont))
function updateControl!(cont::ControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex})
  @debug "Updating control values"
  oldTx = calcControlMatrix(cont)

  if !validateAgainstForwardCalibrationAndSafetyLimit(oldTx, Γ, cont, txCont)
    error("Last control step produced unexpected results! Either your forward calibration is inaccurate or the system is not in the expected state (e.g. amp not on)!" )
  end
  newTx = updateControlMatrix(cont, txCont, Γ, Ω, oldTx)

  if validateAgainstForwardCalibrationAndSafetyLimit(newTx, Ω, cont, txCont) && checkVoltLimits(newTx, cont)
    updateControlSequence!(cont, newTx)
    return true
  else
    @info "Checks" validateAgainstForwardCalibrationAndSafetyLimit(newTx, Ω, cont, txCont) checkVoltLimits(newTx, cont) 
    error("The new tx values are not allowed! Either your forward calibration is inaccurate or the system can not produce the requested field strength!")
    return false
  end
end

# Γ: Matrix from Ref
# Ω: Desired Matrix
# oldTx: Last Set Matrix
function updateControlMatrix(cont::CrossCouplingControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex}, oldTx::Matrix{<:Complex})
  if needsDecoupling(cont.targetSequence)
    β = Γ*inv(oldTx)
  else
    β = diagm(diag(Γ))*inv(diagm(diag(oldTx))) 
  end
  newTx = inv(β)*Ω
  @debug "Last TX matrix [V]:" oldTx
  @debug "Ref matrix [T]:" Γ
  @debug "Desired matrix [T]:" Ω
  @debug "New TX matrix [V]:" newTx 
  return newTx
end

function updateControlMatrix(cont::AWControlSequence, txCont::TxDAQController, Γ::Matrix{<:Complex}, Ω::Matrix{<:Complex}, oldTx::Matrix{<:Complex})
  # For now we completely ignore coupling and hope that it can find good values anyways
  # The problem is, that to achieve 0 we will always output zero, but we would need a much more sophisticated method to solve this
  newTx = oldTx./Γ.*Ω
  if any(isnan.(newTx))
    @warn "There were zeros in the reference signal!" any(iszero.(Γ)) findall(iszero.(Γ))
    newTx[isnan.(newTx)] .= 0.0
  end

  # handle DC separately:
  if txCont.params.controlDC
    push!(cont.dcSearch, (V=oldTx[:,1], B=Γ[:,1]))
    @debug "History of dcSearch" cont.dcSearch
    if length(cont.dcSearch)==1
      my_sign(x) = if x<0; -1 else 1 end
      testOffset = real.(Ω[:,1])*u"T" .- 2u"mT"*my_sign.(real.(Ω[:,1]))
      newTx[:,1] = ustrip.(u"V", testOffset.*[abs(calibration(dependency(txCont, AbstractDAQ), id(channel))(0)) for channel in getControlledChannels(cont)]) 
    else
      last = cont.dcSearch[end]
      previous = cont.dcSearch[end-1]
      if any(abs.(last.B.-previous.B) .< 0.005*real.(Ω[:,1])) # if the last two DC search steps are too close together (especially when close to zero) the next step might produce wrong results
        @info "Restarting DC Search"
        newTx[:,1] = ustrip.(u"V", real.(Ω[:,1])*u"T".*[abs(calibration(dependency(txCont, AbstractDAQ), id(channel))(0)) for channel in getControlledChannels(cont)]) 
      else
        newTx[:,1] .= previous.V .- ((previous.B.-Ω[:,1]).*(last.V.-previous.V))./(last.B.-previous.B)
      end
    end
  end

  #@debug "Last TX matrix [V]:" oldTx=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(oldTx,cont,return_time_signal=true)')
  #@debug "Ref matrix [T]:" Γ=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(Γ,cont,return_time_signal=true)')
  #@debug "Desired matrix [V]:" Ω=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(Ω,cont,return_time_signal=true)')
  #@debug "New TX matrix [T]:" newTx=lineplot(1:rxNumSamplingPoints(cont.currSequence),checkVoltLimits(newTx,cont,return_time_signal=true)')

  return newTx
end

#################################################################################
########## Functions for calculating the field matrix in T from the reference channels
#################################################################################

function calcFieldsFromRef(cont::CrossCouplingControlSequence, uRef::Array{Float32, 4})
  len = numControlledChannels(cont)
  N = rxNumSamplingPoints(cont.currSequence)
  dividers = divider.(getPrimaryComponents(cont))
  frequencies = ustrip(u"Hz", txBaseFrequency(cont.currSequence))  ./ dividers

  Γ = zeros(ComplexF64, len, len, size(uRef, 3), size(uRef, 4))
  sorted = uRef[:, cont.refIndices, :, :]
  for i = 1:size(Γ, 4)
    for j = 1:size(Γ, 3)
      _calcFieldFromRef!(view(Γ, :, :, j, i), cont, view(sorted, :, :, j, i), SortedRef())
    end
  end
  for d =1:len
    c = ustrip(u"T/V", 1 ./cont.refTFs[d](frequencies[d]))
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
  spectrum = rfft(uRef[:, cont.refIndices, :, :], 1)
  spectrum ./= 0.5N
  spectrum[1,:,:,:] ./= 2
  sortedSpectrum = permutedims(spectrum, (2,1,3,4))
  return sortedSpectrum./cont.cachedTFs
end

function _calcFieldFromRef!(Γ::AbstractArray{ComplexF64, 2}, cont::CrossCouplingControlSequence, uRef, ::SortedRef)
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
      desiredField[i,1] = ustrip(u"T", offset(channel))
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
  oldTx = zeros(ComplexF64, controlMatrixShape(cont))
  for (i, channel) in enumerate(getControlledChannels(cont))
    for (j, comp) in enumerate(periodicElectricalComponents(channel))
      oldTx[i, j] = ustrip(u"V", amplitude(comp)) * exp(im*ustrip(u"rad", phase(comp)))
    end
  end
  return oldTx
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
        offset!(channel, real(newTx[i,1])*1.0u"V")
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


function calcExpectedField(tx::Matrix{<:Complex}, cont::CrossCouplingControlSequence)
  dividers = divider.(getPrimaryComponents(cont))
  frequencies = ustrip(u"Hz", txBaseFrequency(cont.currSequence))  ./ dividers
  calibFieldToVoltEstimate = [ustrip(u"V/T", chan.calibration(frequencies[i])) for (i,chan) in enumerate(getControlledDAQChannels(cont))]
  B_fw = tx ./ calibFieldToVoltEstimate
  return B_fw
end

function calcExpectedField(tx::Matrix{<:Complex}, cont::AWControlSequence)
  N = rxNumSamplingPoints(cont.currSequence)
  frequencies = ustrip.(u"Hz",rfftfreq(N, rxSamplingRate(cont.currSequence)))
  calibFieldToVoltEstimate = reduce(vcat,transpose([ustrip.(u"V/T", chan.calibration(frequencies)) for chan in getControlledDAQChannels(cont)]))
  @debug "calcExpectedField" any(calibFieldToVoltEstimate.==0) any(isnan.(tx))
  B_fw = tx ./ calibFieldToVoltEstimate
  return B_fw
end

function validateAgainstForwardCalibrationAndSafetyLimit(tx::Matrix{<:Complex}, B::Matrix{<:Complex}, cont::ControlSequence, txCont::TxDAQController)
  # step 1 apply forward calibration to tx -> B_fw
  B_fw = calcExpectedField(tx, cont)
  
  # step 2 check B_fw against B (rel. and abs. Accuracy)
  forwardCalibrationAgrees = isapprox.(abs.(B_fw), abs.(B), rtol = txCont.params.fieldToVoltRelDeviation, atol=ustrip(u"T",txCont.params.fieldToVoltAbsDeviation))
  
  # step 3 check if B_fw and B are both below safety limit
  isSafe(Btest) = abs.(Btest).<ustrip(u"T",txCont.params.maxField)

  @debug "validateAgainstForwardCalibrationAndSafetyLimit" findmax(abs.(B_fw)) findmax(abs.(B)) all(forwardCalibrationAgrees) all(isSafe(B_fw)) all(isSafe(B))

  return all(forwardCalibrationAgrees) && all(isSafe(B)) && all(isSafe(B_fw))
end

function checkVoltLimits(newTx::Matrix{<:Complex}, cont::CrossCouplingControlSequence)
  validChannel = zeros(Bool, size(newTx, 1))
  for i = 1:size(newTx, 1)
    max = sum(abs.(newTx[i, :]))
    validChannel[i] = max < ustrip(u"V", getControlledDAQChannels(cont)[i].limitPeak)
  end
  valid = all(validChannel)
  if !valid
    @debug "Valid Tx Channel" validChannel newTx
    @warn "New control sequence exceeds voltage limits of tx channel"
  end
  return valid
end

function checkVoltLimits(newTx::Matrix{<:Complex}, cont::AWControlSequence; return_time_signal=false)
  if cont.maxIndex == size(cont.rfftIndices,3)
    N = rxNumSamplingPoints(cont.currSequence)
  else
    N = 2cont.maxIndex-2
  end

  spectrum = copy(newTx[:,1:cont.maxIndex])*0.5N
  spectrum[:,1] .*= 2
  testSignalTime = irfft(spectrum, N, 2)

  if return_time_signal
    return testSignalTime
  else
    slew_rate = (diff(testSignalTime, dims=2)*u"V"*rxSamplingRate(cont.currSequence)) .|> u"V/µs"
    validSlew = maximum(abs.(slew_rate), dims=2) .< getproperty.(getControlledDAQChannels(cont),:limitSlewRate)
    validPeak = maximum(abs.(testSignalTime), dims=2) .< ustrip.(u"V", getproperty.(getControlledDAQChannels(cont),:limitPeak))
  
    valid = all(validSlew) && all(validPeak)
    @debug "Check Volt Limit" p=lineplot(1:N,testSignalTime', canvas=DotCanvas, border=:ascii) maximum(abs.(testSignalTime), dims=2) maximum(abs.(slew_rate), dims=2)
    if !valid
      @debug "Valid Tx Channel" validSlew validPeak
      @warn "New control sequence exceeds voltage limits (slew rate or peak) of tx channel"
    end
    return valid
  end
end
