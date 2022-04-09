export SimulatedRobot, SimulatedRobotParams

Base.@kwdef struct SimulatedRobotParams <: DeviceParams
  defaultVelocity::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,500],[0,400],[0,250]]u"mm"
  namedPositions::Dict{String, Vector{typeof(1.0u"mm")}} = Dict("origin" => [0,0,0]u"mm")
  movementOrder::String = "default"
  coordinateSystem::ScannerCoordinateSystem = ScannerCoordinateSystem(3)
end

SimulatedRobotParams(dict::Dict) = params_from_dict(SimulatedRobotParams, prepareRobotDict(dict))
Base.@kwdef mutable struct SimulatedRobot <: Robot
  @add_device_fields SimulatedRobotParams

  state::RobotState = INIT
  referenced::Bool = false
  position::Vector{typeof(1.0u"mm")} = [0,0,0]u"mm"
  connected::Bool = false
end

Base.close(rob::SimulatedRobot) = nothing

_isReferenced(rob::SimulatedRobot) = rob.referenced

dof(rob::SimulatedRobot) = 3
_getPosition(rob::SimulatedRobot) = rob.position
axisRange(rob::SimulatedRobot) = rob.params.axisRange
movementOrder(rob::SimulatedRobot) = rob.params.movementOrder

function _moveAbs(rob::SimulatedRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  @debug "SimulatedRobot: Moving to position $("["*join([string(x) for x in pos], ", ")*"]")."
  vel = speed!==nothing ? speed : rob.params.defaultVelocity
  projected_time = maximum(abs.(rob.position-pos)./vel)
  sleep(ustrip(u"s",projected_time))
  rob.position = pos
  @debug "SimulatedRobot: Movement completed"
end

function _moveRel(rob::SimulatedRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  @debug "SimulatedRobot: Moving distance $("["*join([string(x) for x in dist], ", ")*"]")"
  vel = speed!==nothing ? speed : rob.params.defaultVelocity
  projected_time = maximum(abs.(dist)./vel)
  sleep(ustrip(u"s",projected_time))
  rob.position += dist
  @debug "SimulatedRobot: Movement completed"
end

function _enable(rob::SimulatedRobot)
  @debug "SimulatedRobot enabled"
end

function _disable(rob::SimulatedRobot)
  @debug "SimulatedRobot disabled"
end

function _reset(rob::SimulatedRobot)
  @debug "SimulatedRobot reset"
  rob.connected = false
end

function _setup(rob::SimulatedRobot)
  @debug "SimulatedRobot setup"
  rob.connected = true
  sleep(0.5)
  @debug "SimulatedRobot: Finished setup"
end

function _doReferenceDrive(rob::SimulatedRobot)
  @debug "SimulatedRobot: Doing reference drive"
  sleep(2)
  @debug "SimulatedRobot: Reference drive complete"
  rob.referenced = true
end

