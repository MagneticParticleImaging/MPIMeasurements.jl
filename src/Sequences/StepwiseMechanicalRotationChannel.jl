export StepwiseMechanicalRotationChannel

export MechanicalRotationDirection
@enum MechanicalRotationDirection begin
  MECHANICAL_ROTATION_DIRECTION_FORWARD
  MECHANICAL_ROTATION_DIRECTION_BACKWARD
  MECHANICAL_ROTATION_DIRECTION_STANDSTILL
end

"Mechanical channel with a triggered stepwise rotation."
Base.@kwdef struct StepwiseMechanicalRotationChannel <: MechanicalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Step angle of the mechanical rotation."
  stepAngle::typeof(1.0u"rad") = 1.0u"°"
  "Rotation direction of the mechanical rotation."
  direction::MechanicalRotationDirection = MECHANICAL_ROTATION_DIRECTION_STANDSTILL
  "Priority of the channel within the stepping process."
  stepPriority::Integer = 99

  "Pause time prior to the step."
  preStepPause::typeof(1.0u"s") = 0.0u"s"
  "Pause time after the step."
  postStepPause::typeof(1.0u"s") = 0.0u"s"
end

channeltype(::Type{<:StepwiseMechanicalRotationChannel}) = StepwiseTxChannel()
mechanicalMovementType(::Type{<:StepwiseMechanicalRotationChannel}) = RotationTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{StepwiseMechanicalRotationChannel}, channelDict::Dict{String, Any})
  splattingDict = Dict{Symbol, Any}()

  if haskey(channelDict, "stepAngle")
    splattingDict[:stepAngle] = uconvert(u"rad", uparse(channelDict["stepAngle"]))
  end

  if haskey(channelDict, "direction")
    if channelDict["direction"] == "forward"
      splattingDict[:direction] = MECHANICAL_ROTATION_DIRECTION_FORWARD
    elseif channelDict["direction"] == "backward"
      splattingDict[:direction] = MECHANICAL_ROTATION_DIRECTION_BACKWARD
    elseif channelDict["direction"] == "forward"
      splattingDict[:direction] = MECHANICAL_ROTATION_DIRECTION_STANDSTILL
    else
      error("The value `$(channelDict["direction"])` is not a valid direction.")
    end
  end

  if haskey(channelDict, "stepPriority")
    splattingDict[:stepPriority] = channelDict["stepPriority"]
  end

  if haskey(channelDict, "preStepPause")
    splattingDict[:preStepPause] = uconvert(u"s", uparse(channelDict["preStepPause"]))
  end

  if haskey(channelDict, "postStepPause")
    splattingDict[:postStepPause] = uconvert(u"s", uparse(channelDict["postStepPause"]))
  end

  return StepwiseMechanicalRotationChannel(;id=channelID, splattingDict...)
end

export stepPriority
stepPriority(channel::StepwiseMechanicalRotationChannel) = channel.stepPriority

export preStepPause
preStepPause(channel::StepwiseMechanicalRotationChannel) = channel.preStepPause

export postStepPause
postStepPause(channel::StepwiseMechanicalRotationChannel) = channel.postStepPause

export cycleDuration
cycleDuration(channel::StepwiseMechanicalRotationChannel, baseFrequency::typeof(1.0u"Hz")) = nothing

export stepsPerCycle
stepsPerCycle(channel::StepwiseMechanicalRotationChannel) = round(Int64, 2π/channel.stepAngle)