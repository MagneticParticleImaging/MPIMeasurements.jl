export SimulatedRobot, SimulatedRobotParams

Base.@kwdef struct SimulatedRobotParams <: DeviceParams
    defaultVelocity::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
    axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,500],[0,500],[0,250]]u"mm"
end

mutable struct SimulatedRobot <: Robot
    deviceID::String
    params::SimulatedRobotParams
    state::RobotState
    referenced::Bool
    position::Vector{typeof(1.0u"mm")}
    connected::Bool
    function SimulatedRobot(deviceID::String, params::SimulatedRobotParams)
        return new(deviceID, params, INIT, false, [0,0,0]u"mm", false)
    end
end

isReferenced(rob::SimulatedRobot) = rob.referenced

dof(rob::SimulatedRobot) = 3
getPosition(rob::SimulatedRobot) = rob.position
axisRange(rob::SimulatedRobot) = rob.params.axisRange

function _moveAbs(rob::SimulatedRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    @info "SimulatedRobot: Moving to pos=$pos"
    projected_time = maximum(abs.(rob.position-pos)./rob.params.defaultVelocity)
    sleep(ustrip(u"s",projected_time))
    rob.position = pos
    @info "SimulatedRobot: Movement completed"
end

function _moveRel(rob::SimulatedRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    @info "SimulatedRobot: Moving dist=$dist"
    projected_time = maximum(abs.(dist)./speed)
    sleep(ustrip(u"s",projected_time))
    rob.position += dist
    @info "SimulatedRobot: Movement completed"
end

function _enable(rob::SimulatedRobot)
    @info "SimulatedRobot enabled"
end

function _disable(rob::SimulatedRobot)
    @info "SimulatedRobot disabled"
end

function _reset(rob::SimulatedRobot)
    @info "SimulatedRobot reset"
    rob.connected = false
end

function _setup(rob::SimulatedRobot)
    @info "SimulatedRobot setup"
    rob.connected = true
    sleep(0.5)
    @info "SimulatedRobot: Finished setup"
end

function _doReferenceDrive(rob::SimulatedRobot)
    @info "SimulatedRobot: Doing reference drive"
    sleep(2)
    @info "SimulatedRobot: Reference drive complete"
    rob.referenced = true
end

