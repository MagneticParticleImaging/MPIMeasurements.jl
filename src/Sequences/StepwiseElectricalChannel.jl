export StepwiseElectricalChannel

"""
Electrical channel with a stepwise definition of values.

$FIELDS
"""
Base.@kwdef mutable struct StepwiseElectricalChannel <: AcyclicElectricalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Divider of the component."
  divider::Integer
  "Values corresponding to the individual steps."
  values::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"A")}, Vector{typeof(1.0u"V")}}
  "TBD"
  enable::Vector{Bool} = Bool[]
end

unitIsTesla(chan::StepwiseElectricalChannel) = all(dimension(chan.values) .== [dimension(u"T")])

channeltype(::Type{<:StepwiseElectricalChannel}) = StepwiseTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{StepwiseElectricalChannel}, channelDict::Dict{String, Any})
  divider = channelDict["divider"]
  enable = haskey(channelDict, "enable") ? channelDict["enable"] : Bool[]
  values = parseFieldUnit(channelDict, "values", channelID)

  if mod(divider, length(values)) != 0
    error("The divider $(divider) needs to be a multiple of the $(length(values))")
  end
  
  return StepwiseElectricalChannel(;id=channelID, divider, values, enable)
end

values(channel::StepwiseElectricalChannel) = channel.values
values!(channel::StepwiseElectricalChannel, val::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"A")}, Vector{typeof(1.0u"V")}}) = channel.values = val

cycleDuration(channel::StepwiseElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = upreferred(channel.divider/baseFrequency)
stepsPerCycle(channel::StepwiseElectricalChannel) = length(channel.values)

enableValues(channel::StepwiseElectricalChannel) = 
     isempty(channel.enable) ? ones(Bool, length(channel.values)) : channel.enable