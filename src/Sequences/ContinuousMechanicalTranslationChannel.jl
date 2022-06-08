export ContinuousMechanicalTranslationChannel

"Mechanical channel describing a continuous translational movement."
Base.@kwdef struct ContinuousMechanicalTranslationChannel <: MechanicalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Speed of the channel."
  speed::typeof(1.0u"m/s")
  "Positions that define the endpoints of the movement."
  positions::Tuple{typeof(1.0u"m"), typeof(1.0u"m")}
end

channeltype(::Type{<:ContinuousMechanicalTranslationChannel}) = ContinuousTxChannel()
mechanicalMovementType(::Type{<:ContinuousMechanicalTranslationChannel}) = TranslationTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{ContinuousMechanicalTranslationChannel}, channelDict::Dict{String, Any})
  speed = uparse(channelDict["speed"])
  positions = uparse.(channelDict["positions"])
  return ContinuousMechanicalTranslationChannel(id=channelID, speed=speed, positions=positions)
end

cycleDuration(channel::ContinuousMechanicalTranslationChannel, baseFrequency::typeof(1.0u"Hz")) = upreferred(abs(channel.positions[1]-channel.positions[2])/speed)