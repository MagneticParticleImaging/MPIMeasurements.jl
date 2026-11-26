export ProtocolOffsetElectricalChannel

"""
Offset channnel that gets translated into the correct representation by the `MPSMeasurementProtocol`

$FIELDS
"""
Base.@kwdef mutable struct ProtocolOffsetElectricalChannel{T<:Union{typeof(1.0u"T"),typeof(1.0u"A"),typeof(1.0u"V")}} <: ProtocolTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  offsetStart::T
  offsetStop::T
  numOffsets::Int64
  "Number of drive-field periods measured per offset.
  If `nothing`, the value defined by the other offset channels of the sequence is used, so only
  one channel needs to define it."
  dfPeriodsPerOffset::Union{Nothing, Integer} = nothing
end

channeltype(::Type{<:ProtocolOffsetElectricalChannel}) = StepwiseTxChannel()

function createFieldChannel(channelID::AbstractString, ::Type{<:ProtocolOffsetElectricalChannel}, channelDict::Dict{String, Any})
  offsetStart = parseFieldUnit(channelDict, "offsetStart", channelID)

  offsetStop = parseFieldUnit(channelDict, "offsetStop", channelID)

  numOffsets = channelDict["numOffsets"]

  dfPeriodsPerOffset = get(channelDict, "dfPeriodsPerOffset", nothing)

  return ProtocolOffsetElectricalChannel(;id = channelID, offsetStart = offsetStart, offsetStop = offsetStop,
    numOffsets = numOffsets, dfPeriodsPerOffset = dfPeriodsPerOffset)
end

values(channel::ProtocolOffsetElectricalChannel{T}) where T = collect(range(channel.offsetStart, channel.offsetStop, length = channel.numOffsets))
values(channel::ProtocolOffsetElectricalChannel, isPositive::Bool) = filter(x-> signbit(x) != isPositive, values(channel))

function toDict!(dict, channel::ProtocolOffsetElectricalChannel)
  dict["type"] = string(nameof(typeof(channel)))
  for field in [x for x in fieldnames(typeof(channel)) if !in(x, [:id])]
    val = getproperty(channel, field)
    # `nothing` means "inherit from another channel" and is not a valid TOML value.
    val === nothing && continue
    dict[String(field)] = toDictValue(val)
  end
  return dict
end