include("Waveform.jl")
include("TxChannel.jl")
include("MagneticField.jl")
include("Acquisition.jl")


export GeneralSettings
Base.@kwdef struct GeneralSettings
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
  "General settings/description of the sequence"
  general::GeneralSettings

  "Magnetic fields defined by the sequence."
  fields::Vector{MagneticField}

  "Settings for the acquisition."
  acquisition::AcquisitionSettings
end

function Sequence(filename::AbstractString)
  return sequenceFromTOML(filename)
end

function toDict!(dict, seq::Sequence)
  dict["General"] = toDict(seq.general)
  dict["Fields"] = toDict(seq.fields)
  dict["Acquisition"] = toDict(seq.acquisition)
  return dict
end

export sequenceFromTOML
function sequenceFromTOML(filename::AbstractString)
  sequenceDict = TOML.parsefile(filename)
  return sequenceFromDict(copy(sequenceDict))
end

export sequenceFromDict
function sequenceFromDict(sequenceDict::Dict{String, Any})
  general = sequenceDict["General"]
  acquisition = sequenceDict["Acquisition"]

  splattingDict = Dict{Symbol, Any}()

  # General
  generalSplattingDict = dict_to_splatting(GeneralSettings, general)
  splattingDict[:general] = GeneralSettings(; generalSplattingDict...)

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
    splattingDict[:channels] = sort(channels, by=id)

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
    knownChannels = MPIFiles.concreteSubtypes(TxChannel)
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
name(sequence::Sequence) = sequence.general.name

export description
description(sequence::Sequence) = sequence.general.description

export targetScanner
targetScanner(sequence::Sequence) = sequence.general.targetScanner

export baseFrequency
baseFrequency(sequence::Sequence) = sequence.general.baseFrequency

export fields
fields(sequence::Sequence) = sequence.fields


electricalTxChannels(sequence::Sequence)::Vector{ElectricalTxChannel} = [channel for field in fields(sequence) for channel in electricalTxChannels(field)]
mechanicalTxChannels(sequence::Sequence)::Vector{MechanicalTxChannel} = [channel for field in fields(sequence) for channel in mechanicalTxChannels(field)]
periodicElectricalTxChannels(sequence::Sequence)::Vector{PeriodicElectricalChannel} = [channel for field in fields(sequence) for channel in periodicElectricalTxChannels(field)]
acyclicElectricalTxChannels(sequence::Sequence)::Vector{AcyclicElectricalTxChannel} = [channel for field in fields(sequence) for channel in acyclicElectricalTxChannels(field)]

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
dfBaseFrequency(sequence::Sequence) = baseFrequency(sequence)

export txBaseFrequency
txBaseFrequency(sequence::Sequence) = dfBaseFrequency(sequence) # Alias, since this might not only concern the drivefield

export dfCycle
dfCycle(sequence::Sequence) = lcm(dfDivider(sequence))/dfBaseFrequency(sequence) |> u"s"

export txCycle
txCycle(sequence::Sequence) = dfCycle(sequence) # Alias, since this might not only concern the drivefield

export dfDivider
function dfDivider(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = dfChannels(sequence)
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
dfNumChannels(sequence::Sequence) = length(dfChannels(sequence)) # TODO: How do we integrate the mechanical channels?

dfChannels(sequence::Sequence) = [x for x in periodicElectricalTxChannels(sequence) if isDfChannel(x)]

export dfPhase
function dfPhase(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = dfChannels(sequence)
  maxComponents = maximum([length(channel.components) for channel in channels])
  numPeriods = length(phase(channels[1].components[1])) # Should all be of the same length
  result = zeros(typeof(1.0u"rad"), (numPeriods, dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      for (periodIdx, phase) in enumerate(phase(component))
        result[periodIdx, channelIdx, componentIdx] = phase
      end
    end
  end

  return result
end

export dfStrength
function dfStrength(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = dfChannels(sequence)
  maxComponents = maximum([length(channel.components) for channel in channels])
  numPeriods = length(amplitude(channels[1].components[1])) # Should all be of the same length
  result = zeros(typeof(1.0u"T"), (numPeriods, dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      for (periodIdx, strength) in enumerate(amplitude(component)) # TODO: What do we do if this is in volt? The conversion factor is with the scanner... Remove the volt version?
        result[periodIdx, channelIdx, componentIdx] = strength
      end
    end
  end

  return result
end

export dfWaveform
function dfWaveform(sequence::Sequence) # TODO: How do we integrate the mechanical channels and non-periodic channels and sweeps?
  channels = dfChannels(sequence)
  maxComponents = maximum([length(channel.components) for channel in channels])
  result = fill(WAVEFORM_SINE, (dfNumChannels(sequence), maxComponents))

  for (channelIdx, channel) in enumerate(channels)
    for (componentIdx, component) in enumerate(channel.components)
      result[channelIdx, componentIdx] = waveform(component)
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
acqNumFrames(sequence::Sequence) = acqNumFrames(sequence.acquisition)
acqNumFrames(sequence::Sequence, val) = acqNumFrames(sequence.acquisition, val)

export acqNumAverages
acqNumAverages(sequence::Sequence) = acqNumAverages(sequence.acquisition)
acqNumAverages(sequence::Sequence, val) = acqNumAverages(sequence.acquisition, val)

export acqNumFrameAverages
acqNumFrameAverages(sequence::Sequence) = acqNumFrameAverages(sequence.acquisition)
acqNumFrameAverages(sequence::Sequence, val) = acqNumFrameAverages(sequence.acquisition, val)

export isBackground
isBackground(sequence::Sequence) = isBackground(sequence.acquisition)
isBackground(sequence::Sequence, val) = isBackground(sequence.acquisition, val)

export rxBandwidth
rxBandwidth(sequence::Sequence) = rxBandwidth(sequence.acquisition)

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
rxChannels(sequence::Sequence) = rxChannels(sequence.acquisition)

for T in [Sequence, GeneralSettings, AcquisitionSettings, MagneticField, TxChannel, ContinuousElectricalChannel, ContinuousMechanicalRotationChannel,
  ContinuousMechanicalTranslationChannel, PeriodicElectricalChannel, PeriodicElectricalComponent, SweepElectricalComponent, StepwiseElectricalChannel, 
  StepwiseMechanicalRotationChannel, StepwiseMechanicalTranslationChannel, ArbitraryElectricalComponent]
  @eval begin
    @generated function ==(x::$T, y::$T)
      fieldEqualities = [:(x.$field == y.$field) for field in fieldnames($T)]
      # If "else"-case needs to be implemented, take care to avoid stack overflow/infinite recursion!
      if !isempty(fieldEqualities)
        temp = fieldEqualities[1]
        for i = 2:length(fieldEqualities)
          temp = Expr(:&&, temp, fieldEqualities[i])
        end
        return temp
      end
    end
    @generated function hash(x::$T, h::UInt)
      hashes = [Expr(:(=), :(h), Expr(:call, :hash, :(x.$field), :(h))) for field in fieldnames($T)]
      push!(hashes, Expr(:(=), :(h), Expr(:call, :hash, $T, :(h))))
      return Expr(:block, hashes...)
    end
  end
end