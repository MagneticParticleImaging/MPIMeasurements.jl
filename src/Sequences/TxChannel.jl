export TxChannelType, ContinuousTxChannel, StepwiseTxChannel
abstract type TxChannelType end
struct ContinuousTxChannel <: TxChannelType end
struct StepwiseTxChannel <: TxChannelType end

export TxMechanicalMovementType, RotationTxChannel, TranslationTxChannel
abstract type TxMechanicalMovementType end
struct RotationTxChannel <: TxMechanicalMovementType end
struct TranslationTxChannel <: TxMechanicalMovementType end

export TxChannel, ElectricalTxChannel, AcyclicElectricalTxChannel, MechanicalTxChannel, ProtocolTxChannel, ElectricalComponent
abstract type TxChannel end
abstract type ElectricalTxChannel <: TxChannel end
abstract type AcyclicElectricalTxChannel <: ElectricalTxChannel end
abstract type MechanicalTxChannel <: TxChannel end
abstract type ProtocolTxChannel <: TxChannel end

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

export id
id(channel::TxChannel) = channel.id

export unitIsTesla
unitIsTesla(channel::ElectricalTxChannel) = false #default fallback

function toDict!(dict, channel::TxChannel)
  for field in [x for x in fieldnames((typeof(channel))) if x != :id]
    dict[String(field)] = toDictValue(getproperty(channel, field))
  end
  dict["type"] = string(typeof(channel))
  return dict
end

"""
    parseFieldUnit(channelDict, key, channelId)

Parse `channelDict[key]` with `parsePossibleURange` and convert the result to ampere,
volt or tesla, depending on its dimension, with floating-point values. The float
conversion is required because a plain `uconvert` turns integer values with a prefixed
unit into rationals (`2u"mT"` into `1//500 T`), which fields of type `typeof(1.0u"T")`
inside unions or type parameters cannot hold. Any other dimension is an error naming
`key` and `channelId`.
"""
function parseFieldUnit(channelDict, key, channelId)
  value = parsePossibleURange(channelDict[key])
  if eltype(value) <: Unitful.Current
    return float.(uconvert.(u"A", value))
  elseif eltype(value) <: Unitful.Voltage
    return float.(uconvert.(u"V", value))
  elseif eltype(value) <: Unitful.BField
    return float.(uconvert.(u"T", value))
  else
    error("The value of `$key` in `$channelId` has to be given as a current, a voltage or in tesla. You supplied the type `$(eltype(value))`.")
  end
end

include("PeriodicElectricalChannel.jl")
include("StepwiseElectricalChannel.jl")
include("ContinuousElectricalChannel.jl")
include("ContinuousMechanicalTranslationChannel.jl")
include("StepwiseMechanicalTranslationChannel.jl")
include("StepwiseMechanicalRotationChannel.jl")
include("ContinuousMechanicalRotationChannel.jl")
include("ProtocolOffsetElectricalChannel.jl")