export ProtocolOffsetElectricalChannel

Base.@kwdef mutable struct ProtocolOffsetElectricalChannel{T<:Union{typeof(1.0u"T"),typeof(1.0u"A"),typeof(1.0u"V")}} <: ProtocolTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  offsetStart::T
  offsetStop::T
  numOffsets::Int64
end

channeltype(::Type{<:ProtocolOffsetElectricalChannel}) = StepwiseTxChannel()

function createFieldChannel(channelID::AbstractString, ::Type{<:ProtocolOffsetElectricalChannel}, channelDict::Dict{String, Any})
  offsetStart = uparse.(channelDict["offsetStart"])
  if eltype(offsetStart) <: Unitful.Current
    offsetStart = offsetStart .|> u"A"
  elseif eltype(offsetStart) <: Unitful.Voltage
    offsetStart = offsetStart .|> u"V"
  elseif eltype(offsetStart) <: Unitful.BField
    offsetStart = offsetStart .|> u"T"
  else
    error("The value for an offsetStart has to be either given as a current or in tesla. You supplied the type `$(eltype(tmp))`.")
  end

  offsetStop = uparse.(channelDict["offsetStop"])
  if eltype(offsetStop) <: Unitful.Current
    offsetStop = offsetStop .|> u"A"
  elseif eltype(offsetStop) <: Unitful.Voltage
    offsetStop = offsetStop .|> u"V"
  elseif eltype(offsetStop) <: Unitful.BField
    offsetStop = offsetStop .|> u"T"
  else
    error("The value for an offsetStop has to be either given as a current or in tesla. You supplied the type `$(eltype(tmp))`.")
  end

  numOffsets = channelDict["numOffsets"]

  return ProtocolOffsetElectricalChannel(;id = channelID, offsetStart = offsetStart, offsetStop = offsetStop, numOffsets = numOffsets)
end

values(channel::ProtocolOffsetElectricalChannel{T}) where T = collect(range(channel.offsetStart, channel.offsetStop, length = channel.numOffsets))
values(channel::ProtocolOffsetElectricalChannel, isPositive::Bool) = filter(x-> signbit(x) != isPositive, values(channel))

function toDict!(dict, channel::ProtocolOffsetElectricalChannel)
  dict["type"] = string(typeof(channel))
  for field in [x for x in fieldnames(typeof(channel)) if !in(x, [:id])]
    dict[String(field)] = toDictValue(getproperty(channel, field))
  end
  return dict
end