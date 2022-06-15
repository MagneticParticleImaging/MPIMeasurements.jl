include("Waveform.jl")

export TxChannelType, ContinuousTxChannel, StepwiseTxChannel
abstract type TxChannelType end
struct ContinuousTxChannel <: TxChannelType end
struct StepwiseTxChannel <: TxChannelType end

export TxMechanicalMovementType, RotationTxChannel, TranslationTxChannel
abstract type TxMechanicalMovementType end
struct RotationTxChannel <: TxMechanicalMovementType end
struct TranslationTxChannel <: TxMechanicalMovementType end

export TxChannel, ElectricalTxChannel, AcyclicElectricalTxChannel, MechanicalTxChannel, ElectricalComponent
abstract type TxChannel end
abstract type ElectricalTxChannel <: TxChannel end
abstract type AcyclicElectricalTxChannel <: ElectricalTxChannel end
abstract type MechanicalTxChannel <: TxChannel end

abstract type ElectricalComponent end

export channeltype
channeltype(::Type{<:TxChannelType}) = ContinuousTxChannel() #fallback, by default everything is continuous

export isContinuous
isContinuous(channelType::T) where T <: TxChannel = isContinuous(channeltype(T), channelType)
isContinuous(::ContinuousTxChannel, channel) = true
isContinuous(::StepwiseTxChannel, channel) = false

export isStepwise
isStepwise(channelType::T) where T <: TxChannel = isStepwise(channeltype(T), channelType)
isStepwise(::ContinuousTxChannel, channel) = false
isStepwise(::StepwiseTxChannel, channel) = true

export mechanicalMovementType
@mustimplement mechanicalMovementType(::Type{<:MechanicalTxChannel})

export doesRotationMovement
doesRotationMovement(channelType::T) where T <: MechanicalTxChannel = doesRotationMovement(mechanicalMovementType(T), channelType)
doesRotationMovement(::TxMechanicalMovementType, channel) = false
doesRotationMovement(::RotationTxChannel, channel) = true

export doesTranslationMovement
doesTranslationMovement(channelType::T) where T <: MechanicalTxChannel = doesTranslationMovement(mechanicalMovementType(T), channelType)
doesTranslationMovement(::TxMechanicalMovementType, channel) = false
doesTranslationMovement(::TranslationTxChannel, channel) = true

export stepsPerCycle
stepsPerCycle(channelType::T) where T = channeltype(T) isa StepwiseTxChannel ? error("Method not defined for $T.") : nothing

export cycleDuration
cycleDuration(::T, var) where T <: TxChannel = error("The method has not been implemented for T")

include("PeriodicElectricalChannel.jl")
include("StepwiseElectricalChannel.jl")
include("ContinuousElectricalChannel.jl")
include("ContinuousMechanicalTranslationChannel.jl")
include("StepwiseMechanicalTranslationChannel.jl")
include("StepwiseMechanicalRotationChannel.jl")
include("ContinuousMechanicalRotationChannel.jl")
include("Acquisition.jl")

export MagneticField
"""
Description of a magnetic field.

The field can either be electromagnetically or mechanically changed.
The mechanical movement of e.g. an iron yoke would be defined within
two channels, one electrical and one mechanical.
"""
Base.@kwdef struct MagneticField
  "Unique ID of the field description."
  id::AbstractString
  "Transmit channels that are used for the field."
  channels::Vector{TxChannel}

  "Flag if the start of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeStartInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if a transition of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeTransitionInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the end of the field should be convoluted. In case of an existing brake on
  a mechanical channel this means a use of the brake."
  safeEndInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the field should be convoluted down in case of an error. In case of an
  existing brake on a mechanical channel this means a use of the brake."
  safeErrorInterval::typeof(1.0u"s") = 0.5u"s"

  "Flag if the channels of the field should be controlled."
  control::Bool = true
  "Flag if the field should be decoupled. Not used for mechanical channels."
  decouple::Bool = true
end

export Sequence
"""
Description of a sequence that can be run by a scanner.

The sequence can either be continuous or triggered. Triggered in
this context means that the acquisition is done on a certain event,
e.g. the move of a robot. The sweeping of frequencies or movement points
can also be done in a triggered or continuous fashion.
"""
Base.@kwdef struct Sequence
  "Name of the sequence to identify it."
  name::AbstractString
  "Description of the sequence."
  description::AbstractString
  "The scanner targeted by the sequence."
  targetScanner::AbstractString
  "Base frequency for all channels. Mechanical channels are synchronized
  with the electrical ones by referencing the time required for the movement
  against this frequency. Please note that the latter has uncertainties."
  baseFrequency::typeof(1.0u"Hz")

  "Magnetic fields defined by the sequence."
  fields::Vector{MagneticField}

  "Settings for the acquisition."
  acquisition::AcquisitionSettings
end

function Sequence(filename::AbstractString)
  return sequenceFromTOML(filename)
end

export sequenceFromTOML
function sequenceFromTOML(filename::AbstractString)
  sequenceDict = TOML.parsefile(filename)

  general = sequenceDict["General"]
  acquisition = sequenceDict["Acquisition"]

  splattingDict = Dict{Symbol, Any}()

  # Main section
  splattingDict[:name] = general["name"]
  splattingDict[:description] = general["description"]
  splattingDict[:targetScanner] = general["targetScanner"]
  splattingDict[:baseFrequency] = uparse(general["baseFrequency"])

  # Fields
  splattingDict[:fields] = fieldDictToFields(sequenceDict["Fields"])

  # Acquisition
  acqSplattingDict = Dict{Symbol, Any}()

  acqSplattingDict[:channels] = RxChannel.(acquisition["channels"])
  acqSplattingDict[:bandwidth] = uparse(acquisition["bandwidth"])
  if haskey(acquisition, "numPeriodsPerFrame")
    acqSplattingDict[:numPeriodsPerFrame] = acquisition["numPeriodsPerFrame"]
  end
  if haskey(acquisition, "numFrames")
    acqSplattingDict[:numFrames] = acquisition["numFrames"]
  end
  if haskey(acquisition, "numAverages")
    acqSplattingDict[:numAverages] = acquisition["numAverages"]
  end
  if haskey(acquisition, "numFrameAverages")
    acqSplattingDict[:numFrameAverages] = acquisition["numFrameAverages"]
  end

  splattingDict[:acquisition] = AcquisitionSettings(;acqSplattingDict...)

  sequence =  Sequence(;splattingDict...)

  # TODO: Sanity check on sequence (equal length of triggered vectors etc.)

  return sequence
end

function fieldDictToFields(fieldsDict::Dict{String, Any})
  fields = Vector{MagneticField}()

  rootFields = ["safeStartInterval", "safeTransitionInterval", "safeEndInterval", "safeErrorInterval", "control", "decouple"] # Is reflexion better here?
  for (fieldID, fieldDict) in fieldsDict
    splattingDict = Dict{Symbol, Any}()
    channels = Vector{TxChannel}()
    for (channelID, channelDict) in fieldDict
      # Ignore fields from MagneticField root to get the channels
      if !(channelID in rootFields)
        push!(channels, createFieldChannel(channelID, channelDict))
      else
        splattingDict[Symbol(channelID)] = channelDict
      end
    end
    splattingDict[:id] = fieldID
    splattingDict[:channels] = channels

    if haskey(fieldDict, "safeStartInterval")
      splattingDict[:safeStartInterval] = uparse(fieldDict["safeStartInterval"])
    end
    if haskey(fieldDict, "safeTransitionInterval")
      splattingDict[:safeTransitionInterval] = uparse(fieldDict["safeTransitionInterval"])
    end
    if haskey(fieldDict, "safeEndInterval")
      splattingDict[:safeEndInterval] = uparse(fieldDict["safeEndInterval"])
    end
    if haskey(fieldDict, "safeErrorInterval")
      splattingDict[:safeErrorInterval] = uparse(fieldDict["safeErrorInterval"])
    end

    field = MagneticField(;splattingDict...)
    push!(fields, field)
  end

  return fields
end

# TODO further remove redundant code in channel creation
function createFieldChannel(channelID::AbstractString, channelDict::Dict{String, Any})
  if haskey(channelDict, "type")
    type = pop!(channelDict, "type")
    knownChannels = concreteSubtypes(TxChannel)
    index = findfirst(x -> x == type, string.(knownChannels))
    if !isnothing(index) 
      createFieldChannel(channelID, knownChannels[index], channelDict)
    else
      error("Channel $channelID has an unknown channel type `$type`.")
    end
  else
    error("Channel $channelID has no `type` field.")
  end
end

export name
name(sequence::Sequence) = sequence.name

export description
description(sequence::Sequence) = sequence.description

export targetScanner
targetScanner(sequence::Sequence) = sequence.targetScanner

export baseFrequency
baseFrequency(sequence::Sequence) = sequence.baseFrequency

channels(field::MagneticField) = field.channels
channels(field::MagneticField, T::Type{<:TxChannel}) = [channel for channel in channels(field) if typeof(channel) <: T]

export safeStartInterval
safeStartInterval(field::MagneticField) = field.safeStartInterval
export safeTransitionInterval
safeTransitionInterval(field::MagneticField) = field.safeTransitionInterval
export safeEndInterval
safeEndInterval(field::MagneticField) = field.safeEndInterval
export safeErrorInterval
safeErrorInterval(field::MagneticField) = field.safeErrorInterval

control(field::MagneticField) = field.control
decouple(field::MagneticField) = field.decouple

export electricalTxChannels
electricalTxChannels(field::MagneticField) = channels(field, ElectricalTxChannel)
electricalTxChannels(sequence::Sequence)::Vector{ElectricalTxChannel} = [channel for field in sequence.fields for channel in electricalTxChannels(field)]

export mechanicalTxChannels
mechanicalTxChannels(field::MagneticField) = channels(field, MechanicalTxChannel)
mechanicalTxChannels(sequence::Sequence)::Vector{MechanicalTxChannel} = [channel for field in sequence.fields for channel in mechanicalTxChannels(field)]

export periodicElectricalTxChannels
periodicElectricalTxChannels(field::MagneticField) = channels(field, PeriodicElectricalChannel)
periodicElectricalTxChannels(sequence::Sequence)::Vector{PeriodicElectricalChannel} = [channel for field in sequence.fields for channel in periodicElectricalTxChannels(field)]

export acyclicElectricalTxChannels
acyclicElectricalTxChannels(field::MagneticField) = channels(field, AcyclicElectricalTxChannel)
acyclicElectricalTxChannels(sequence::Sequence)::Vector{AcyclicElectricalTxChannel} = [channel for field in sequence.fields for channel in acyclicElectricalTxChannels(field)]

export continuousElectricalTxChannels
continuousElectricalTxChannels(sequence::Sequence) = [channel for channel in electricalTxChannels(sequence) if isContinuous(channel)]

export continuousMechanicalTxChannels
continuousMechanicalTxChannels(sequence::Sequence) = [channel for channel in mechanicalTxChannels(sequence) if isContinuous(channel)]

export stepwiseElectricalTxChannels
stepwiseElectricalTxChannels(sequence::Sequence) = [channel for channel in electricalTxChannels(sequence) if isStepwise(channel)]

export stepwiseMechanicalTxChannels
stepwiseMechanicalTxChannels(sequence::Sequence) = [channel for channel in mechanicalTxChannels(sequence) if isStepwise(channel)]

export hasElectricalTxChannels
hasElectricalTxChannels(sequence::Sequence) = length(electricalTxChannels(sequence)) > 0

export hasMechanicalTxChannels
hasMechanicalTxChannels(sequence::Sequence) = length(mechanicalTxChannels(sequence)) > 0

export hasPeriodicElectricalTxChannels
hasPeriodicElectricalTxChannels(sequence::Sequence) = length(periodicElectricalTxChannels(sequence)) > 0

export hasAcyclicElectricalTxChannels
hasAcyclicElectricalTxChannels(sequence::Sequence) = length(acyclicElectricalTxChannels(sequence)) > 0

export hasContinuousElectricalTxChannels
hasContinuousElectricalChannels(sequence::Sequence) = any(isContinuous.(electricalTxChannels(sequence)))

export hasStepwiseElectricalChannels
hasStepwiseElectricalChannels(sequence::Sequence) = any(isStepwise.(electricalTxChannels(sequence)))

export hasContinuousMechanicalTxChannels
hasContinuousMechanicalTxChannels(sequence::Sequence) = any(isContinuous.(mechanicalTxChannels(sequence)))

export hasStepwiseMechanicalChannels
hasStepwiseMechanicalChannels(sequence::Sequence) = any(isStepwise.(mechanicalTxChannels(sequence)))

export fields
fields(sequence::Sequence) = sequence.fields

export id
id(channel::TxChannel) = channel.id
id(channel::RxChannel) = channel.id
id(field::MagneticField) = field.id

# Enable sorting of stepwise channels by their step priority
# TODO: This currently blocks sorting for other properties
function Base.isless(a::TxChannel, b::TxChannel)
  if isStepwise(a) && isStepwise(b)
    isless(a.stepPriority, b.stepPriority)
  elseif isStepwise(a)
    return false
  elseif isStepwise(b)
    return true
  else
    return true
  end
end

export amplitude!
function amplitude!(channel::PeriodicElectricalChannel, componentId::AbstractString, value::Union{typeof(1.0u"T"),typeof(1.0u"V")}; period::Integer=1)
  index = findfirst(x -> id(x) == componentId, channel.components)
  if !isnothing(index)
    amplitude!(channel.components[index], value, period = period)
  else
    throw(ArgumentError("Channel $(id(channel)) has no component with id $componentid"))
  end
end

export phase!
function phase!(channel::PeriodicElectricalChannel, componentId::AbstractString, value::typeof(1.0u"rad"); period::Integer=1)
  index = findfirst(x -> id(x) == componentId, channel.components)
  if !isnothing(index)
    phase!(channel.components[index], value, period = period)
  else
    throw(ArgumentError("Channel $(id(channel)) has no component with id $componentid"))
  end
end

export acqGradient
acqGradient(sequence::Sequence) = nothing # TODO: Implement

export acqNumPeriodsPerFrame
function acqNumPeriodsPerFrame(sequence::Sequence)
  #TODO: We can't limit this to acyclic channels. What is the correct number of periods per frame with mechanical channels?
  if hasAcyclicElectricalTxChannels(sequence)
    channels = acyclicElectricalTxChannels(sequence)
    samplesPerCycle = lcm(dfDivider(sequence))
    numPeriods = [div(c.divider, samplesPerCycle) for c in channels ]

    if minimum(numPeriods) != maximum(numPeriods)
      error("Sequence contains acyclic electrical channels of different length: $(numPeriods)")
    end
    return first(numPeriods)
  else
    #channels = electricalTxChannels(sequence)
    return sequence.acquisition.numPeriodsPerFrame # round(Int64, lcm(dfDivider(sequence))/minimum(dfDivider(sequence)))
  end
end

export acqNumPeriodsPerPatch
function acqNumPeriodsPerPatch(sequence::Sequence)
  #TODO: We can't limit this to acyclic channels. What is the correct number of periods per frame with mechanical channels?
  if hasAcyclicElectricalTxChannels(sequence)
    channels = acyclicElectricalTxChannels(sequence)
    samplesPerCycle = lcm(dfDivider(sequence))
    stepsPerCycle = [ typeof(c) <: StepwiseElectricalChannel ?
                              div(c.divider,length(c.values)*samplesPerCycle) :
                              div(c.dividerSteps,samplesPerCycle) for c in channels ]
    if minimum(stepsPerCycle) != maximum(stepsPerCycle)
      error("Sequence contains acyclic electrical channels of different length: $(stepsPerCycle)")
    end
    return first(stepsPerCycle)
  else
    return 1
  end
end

export acqNumPatches
acqNumPatches(sequence::Sequence) = div(acqNumPeriodsPerFrame(sequence), acqNumPeriodsPerPatch(sequence))

export acqOffsetField
acqOffsetField(sequence::Sequence) = nothing # TODO: Implement

export dfBaseFrequency
dfBaseFrequency(sequence::Sequence) = sequence.baseFrequency

export txBaseFrequency
txBaseFrequency(sequence::Sequence) = dfBaseFrequency(sequence) # Alias, since this might not only concern the drivefield

export dfCycle
dfCycle(sequence::Sequence) = lcm(dfDivider(sequence))/dfBaseFrequency(sequence) |> u"s"

export txCycle
txCycle(sequence::Sequence) = dfCycle(sequence) # Alias, since this might not only concern the drivefield

export dfDivider
function dfDivider(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = periodicElectricalTxChannels(sequence)
  maxComponents = maximum([length(channel.components) for channel in channels])
  result = zeros(Int64, (dfNumChannels(sequence), maxComponents))
  
  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      result[channelIdx, componentIdx] = component.divider
    end
  end

  return result
end

export dfNumChannels
dfNumChannels(sequence::Sequence) = length(periodicElectricalTxChannels(sequence)) # TODO: How do we integrate the mechanical channels?

export dfPhase
function dfPhase(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = periodicElectricalTxChannels(sequence)
  maxComponents = maximum([length(channel.components) for channel in channels])
  numPeriods = length(channels[1].components[1].phase) # Should all be of the same length
  result = zeros(typeof(1.0u"rad"), (numPeriods, dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      for (periodIdx, phase) in enumerate(component.phase)
        result[periodIdx, channelIdx, componentIdx] = phase
      end
    end
  end

  return result
end

export dfStrength
function dfStrength(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = [channel for field in sequence.fields for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel]
  maxComponents = maximum([length(channel.components) for channel in channels])
  numPeriods = length(channels[1].components[1].amplitude) # Should all be of the same length
  result = zeros(typeof(1.0u"T"), (numPeriods, dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      for (periodIdx, strength) in enumerate(component.amplitude) # TODO: What do we do if this is in volt? The conversion factor is with the scanner... Remove the volt version?
        result[periodIdx, channelIdx, componentIdx] = strength
      end
    end
  end

  return result
end

export dfWaveform
function dfWaveform(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = [channel for field in sequence.fields for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel]
  maxComponents = maximum([length(channel.components) for channel in channels])
  result = fill(WAVEFORM_SINE, (dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      result[channelIdx, componentIdx] = component.waveform
    end
  end

  return result
end

export needsControl
needsControl(sequence::Sequence) = any([control(field) for field in fields(sequence)])

export needsDecoupling
needsDecoupling(sequence::Sequence) = any([decouple(field) for field in fields(sequence)])

export needsControlOrDecoupling
needsControlOrDecoupling(sequence::Sequence) = needsControl(sequence) || needsDecoupling(sequence)

# Functions working on the acquisition are define here because they need Sequence to be defined
export acqNumFrames
acqNumFrames(sequence::Sequence) = sequence.acquisition.numFrames
acqNumFrames(sequence::Sequence, val) = sequence.acquisition.numFrames = val

export acqNumAverages
acqNumAverages(sequence::Sequence) = sequence.acquisition.numAverages
acqNumAverages(sequence::Sequence, val) = sequence.acquisition.numAverages = val

export acqNumFrameAverages
acqNumFrameAverages(sequence::Sequence) = sequence.acquisition.numFrameAverages
acqNumFrameAverages(sequence::Sequence, val) = sequence.acquisition.numFrameAverages = val

export isBackground
isBackground(sequence::Sequence) = sequence.acquisition.isBackground
isBackground(sequence::Sequence, val) = sequence.acquisition.isBackground = val

export rxBandwidth
rxBandwidth(sequence::Sequence) = sequence.acquisition.bandwidth

export rxSamplingRate
rxSamplingRate(sequence::Sequence) = 2 * rxBandwidth(sequence)

export rxNumChannels
rxNumChannels(sequence::Sequence) = length(rxChannels(sequence))

export rxNumSamplingPoints
function rxNumSamplingPoints(sequence::Sequence)
  result = upreferred(rxSamplingRate(sequence)*dfCycle(sequence))
  if !isinteger(result)
    throw(ScannerConfigurationError("The selected combination of divider and decimation results in non-integer sampling points."))
  end

  return Int64(result)
end

export rxNumSamplesPerPeriod
rxNumSamplesPerPeriod(sequence::Sequence) = rxNumSamplingPoints(sequence)

export rxChannels
rxChannels(sequence::Sequence) = sequence.acquisition.channels