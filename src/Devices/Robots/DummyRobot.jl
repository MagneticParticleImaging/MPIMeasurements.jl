export DummyRobot, DummyRobotParams

Base.@kwdef struct DummyRobotParams <: DeviceParams
end

DummyRobotParams(dict::Dict) = params_from_dict(DummyRobotParams, dict)

Base.@kwdef mutable struct DummyRobot <: Robot
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyRobotParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  state::RobotState = INIT
  referenced::Bool = false
end

_isReferenced(rob::DummyRobot) = rob.referenced

_getPosition(rob::DummyRobot) = [1.0,0.0,0.0]u"mm"
dof(rob::DummyRobot) = 3
axisRange(rob::DummyRobot) = [[-Inf, Inf], [-Inf, Inf], [-Inf, Inf]]u"m"

function _moveAbs(rob::DummyRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  @debug "DummyRobot: movAbs pos=$pos"
end

function _moveRel(rob::DummyRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  @debug "DummyRobot: movRel dist=$dist"
end

function _enable(rob::DummyRobot)
  @debug "DummyRobot: enable"
end

function _disable(rob::DummyRobot)
  @debug "DummyRobot: disable"
end

function _reset(rob::DummyRobot)
  @debug "DummyRobot: reset"
end

function _setup(rob::DummyRobot)
  @debug "DummyRobot: setup"
end

function _doReferenceDrive(rob::DummyRobot)
  @debug "DummyRobot: Doing reference drive"
  rob.referenced = true
end
