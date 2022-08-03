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

export id
id(channel::TxChannel) = channel.id

function toDict!(dict, channel::TxChannel)
  for field in [x for x in fieldnames((typeof(channel))) if x != :id]
    dict[String(field)] = toDictValue(getproperty(channel, field))
  end
  dict["type"] = string(typeof(channel))
  return dict
end

toDictValue(channel::TxChannel) = toDict(channel)

include("PeriodicElectricalChannel.jl")
include("StepwiseElectricalChannel.jl")
include("ContinuousElectricalChannel.jl")
include("ContinuousMechanicalTranslationChannel.jl")
include("StepwiseMechanicalTranslationChannel.jl")
include("StepwiseMechanicalRotationChannel.jl")
include("ContinuousMechanicalRotationChannel.jl")