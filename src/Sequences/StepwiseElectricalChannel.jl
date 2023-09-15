export StepwiseElectricalChannel

"Electrical channel with a stepwise definition of values."
Base.@kwdef struct StepwiseElectricalChannel <: AcyclicElectricalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Divider of the component."
  divider::Integer
  "Values corresponding to the individual steps."
  values::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"A")}, Vector{typeof(1.0u"V")}}
  "TBD"
  enable::Vector{Bool} = Bool[]
end

channeltype(::Type{<:StepwiseElectricalChannel}) = StepwiseTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{StepwiseElectricalChannel}, channelDict::Dict{String, Any})
  divider = channelDict["divider"]
  enable = haskey(channelDict, "enable") ? parsePossibleURange(channelDict["enable"]) : Bool[]
  values = parsePossibleURange(channelDict["values"])
  if eltype(values) <: Unitful.Current
    values = values .|> u"A"
  elseif eltype(values) <: Unitful.Voltage
    values = values .|> u"V"
  elseif eltype(values) <: Unitful.BField
    values = values .|> u"T"
  else
    error("The values have to be either given as a current or in Tesla. You supplied the type `$(eltype(values))`.")
  end

  if mod(divider, length(values)) != 0
    error("The divider $(divider) needs to be a multiple of the $(length(values))")
  end
  
  return StepwiseElectricalChannel(;id=channelID, divider, values, enable)
end

values(channel::StepwiseElectricalChannel) = channel.values

cycleDuration(channel::StepwiseElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = upreferred(channel.divider/baseFrequency)
stepsPerCycle(channel::StepwiseElectricalChannel) = length(channel.values)

enableValues(channel::StepwiseElectricalChannel) = 
     isempty(channel.enable) ? ones(Bool, length(channel.values)) : channel.enable