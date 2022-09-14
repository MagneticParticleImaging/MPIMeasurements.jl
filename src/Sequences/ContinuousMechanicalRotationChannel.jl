export ContinuousMechanicalRotationChannel

"Mechanical channel with a continuous rotation."
Base.@kwdef struct ContinuousMechanicalRotationChannel <: MechanicalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Frequency of the mechanical rotation."
  divider::Integer
  "Phase of the mechanical rotation."
  phase::typeof(1.0u"rad")
end

channeltype(::Type{<:ContinuousMechanicalRotationChannel}) = ContinuousTxChannel()
mechanicalMovementType(::Type{<:ContinuousMechanicalRotationChannel}) = RotationTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{ContinuousMechanicalRotationChannel}, channelDict::Dict{String, Any})
  divider = Int64.(channelDict["divider"])
  phase = uconvert.(u"rad", uparse.(channelDict["phase"]))
  return ContinuousMechanicalRotationChannel(id=channelID, divider=divider, phase=phase)
end

cycleDuration(channel::ContinuousMechanicalRotationChannel, baseFrequency::typeof(1.0u"Hz")) = baseFrequency/channel.divider