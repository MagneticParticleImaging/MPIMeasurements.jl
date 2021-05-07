export DummyRobot, DummyRobotParams

Base.@kwdef struct DummyRobotParams <: DeviceParams
end

mutable struct DummyRobot <: Robot
    deviceID::String
    params::DummyRobotParams
    state::RobotState
    referenced::Bool
    function DummyRobot(deviceID::String, params::DummyRobotParams)
        return new(deviceID, params, INIT, false)
    end
end

state(rob::DummyRobot) = rob.state
setstate!(rob::DummyRobot, state::RobotState) = rob.state=state
isReferenced(rob::DummyRobot) = rob.referenced

getPosition(rob::DummyRobot) = [1.0,0.0,0.0]u"mm"
dof(rob::DummyRobot) = 3
axisRange(rob::DummyRobot) = [[-Inf, Inf], [-Inf, Inf], [-Inf, Inf]]u"m"

function _moveAbs(rob::DummyRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    @info "DummyRobot: movAbs pos=$pos"
end

function _moveRel(rob::DummyRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    @info "DummyRobot: movRel dist=$dist"
end

function _enable(rob::DummyRobot)
    @info "DummyRobot: enable"
end

function _disable(rob::DummyRobot)
    @info "DummyRobot: disable"
end

function _reset(rob::DummyRobot)
    @info "DummyRobot: reset"
end

function _setup(rob::DummyRobot)
    @info "DummyRobot: setup"
end

function _doReferenceDrive(rob::DummyRobot)
    @info "DummyRobot: Doing reference drive"
    rob.referenced = true
end
