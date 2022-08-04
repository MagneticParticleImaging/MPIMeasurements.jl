export StepwiseMechanicalTranslationChannel

"Mechanical channel describing a stepwise translational movement."
Base.@kwdef struct StepwiseMechanicalTranslationChannel <: MechanicalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Speed of the channel. If defined as a vector, this must have a length of length(positions)-1."
  speed::Union{typeof(1.0u"m/s"), Vector{typeof(1.0u"m/s")}}
  "Positions that define the steps of the movement."
  positions::Vector{typeof(1.0u"m")}
  "Priority of the channel within the stepping process."
  stepPriority::Integer = 99

  "Pause time prior to the step."
  preStepPause::typeof(1.0u"s") = 0.0u"s"
  "Pause time after the step."
  postStepPause::typeof(1.0u"s") = 0.0u"s"
end

channeltype(::Type{<:StepwiseMechanicalTranslationChannel}) = StepwiseTxChannel()
mechanicalMovementType(::Type{<:StepwiseMechanicalTranslationChannel}) = TranslationTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{StepwiseMechanicalTranslationChannel}, channelDict::Dict{String, Any})
  speed = uparse(channelDict["speed"])
  positions = uparse.(channelDict["positions"])

  splattingDict = Dict{Symbol, Any}()

  if haskey(channelDict, "stepPriority")
    splattingDict[:stepPriority] = channelDict["stepPriority"]
  end

  if haskey(channelDict, "preStepPause")
    splattingDict[:preStepPause] = uconvert(u"s", uparse(channelDict["preStepPause"]))
  end

  if haskey(channelDict, "postStepPause")
    splattingDict[:postStepPause] = uconvert(u"s", uparse(channelDict["postStepPause"]))
  end

  return StepwiseMechanicalTranslationChannel(;id=channelID, speed, positions, splattingDict...)
end

export stepPriority
stepPriority(channel::StepwiseMechanicalTranslationChannel) = channel.stepPriority

export preStepPause
preStepPause(channel::StepwiseMechanicalTranslationChannel) = channel.preStepPause

export postStepPause
postStepPause(channel::StepwiseMechanicalTranslationChannel) = channel.postStepPause

export cycleDuration
cycleDuration(channel::StepwiseMechanicalTranslationChannel, baseFrequency::typeof(1.0u"Hz")) = nothing

export stepsPerCycle
stepsPerCycle(channel::StepwiseMechanicalTranslationChannel) = length(channel.positions)