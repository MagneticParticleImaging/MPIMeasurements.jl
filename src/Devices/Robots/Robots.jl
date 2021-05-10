using Graphics: @mustimplement
using Unitful
# using OptionalUnits

import Base: reset

export Robot, RobotState, getPosition, dof, state, isReferenced, moveAbs, moveRel, enable, disable, reset, setup, doReferenceDrive, axisRange, defaultVelocity

@enum RobotState INIT DISABLED READY MOVING ERROR

abstract type Robot <: Device end

state(rob::Robot) = rob.state
setstate!(rob::Robot, state::RobotState) = rob.state=state
@mustimplement isReferenced(rob::Robot)
@mustimplement getPosition(rob::Robot)
@mustimplement dof(rob::Robot)
@mustimplement axisRange(rob::Robot) # must return Vector of Vectors

defaultVelocity(rob::Robot) = nothing # should be implemented for a robot that can handle velocities

@mustimplement _moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
@mustimplement _moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
@mustimplement _enable(rob::Robot)
@mustimplement _disable(rob::Robot)
@mustimplement _reset(rob::Robot)
@mustimplement _setup(rob::Robot)
@mustimplement _doReferenceDrive(rob::Robot)

include("DummyRobot.jl")
include("SimulatedRobot.jl")
include("IgusRobot.jl")
include("IselRobot.jl")
include("Safety.jl")
include("KnownSetups.jl")

moveAbs(rob::Robot, pos::Vararg{Unitful.Length,N}) where N = moveAbs(rob, [pos...])
moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}) = moveAbs(rob, pos, defaultVelocity(rob))
moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Unitful.Velocity) = moveAbs(rob, pos, speed * ones(dof(rob)))

function moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

    @assert length(pos) == dof(rob) "Position vector included $(length(pos)) axes, but the robot has $(dof(rob)) degrees-of-freedom"
    @assert state(rob) == READY "Robot is currently in state $(state(rob)), to start a movement it has to be in state READY"
    @assert isReferenced(rob) "Robot has to be referenced for absolute movement!" # TODO: maybe this does not have to be limited
    
    @assert checkAxisRange(rob, pos) "Final position $(pos) is out of the robots axes range."
    #TODO: perform safety check of coordinates

    setstate!(rob, MOVING)
    try
        @info "Started absolute robot movement to $pos with $speed."
        _moveAbs(rob, pos, speed)
        setstate!(rob, READY)
    catch exc
        @error "Some error occured during the robot drive" exc
        setstate!(rob, ERROR)
    end
end

moveRel(rob::Robot, dist::Vararg{Unitful.Length,N}) where N = moveRel(rob, [dist...])
moveRel(rob::Robot, dist::Vector{<:Unitful.Length}) = moveRel(rob, dist, defaultVelocity(rob))
moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Unitful.Velocity) = moveRel(rob, dist, speed * ones(dof(rob)))

function moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

    @assert length(dist) == dof(rob) "Distance vector included $(length(dist)) axes, but the robot has $(dof(rob)) degrees-of-freedom"
    @assert state(rob) == READY "Robot is currently in state $(state(rob)), to start a movement it has to be in state READY"
    
    pos = getPosition(rob) + dist
    @assert checkAxisRange(rob, pos) "Final position $(pos) is out of the robots axes range."
    #TODO: perform safety check of coordinates
    
    setstate!(rob, MOVING)
    
    try
        _moveRel(rob, dist, speed)
        setstate!(rob, READY)
    catch exc
        @error "Some error occured during the robot drive" exc
        setstate!(rob, ERROR)
    end
end

function enable(rob::Robot)
    if state(rob) == READY
        return
    elseif state(rob) == DISABLED
        _enable(rob)
        setstate!(rob, READY)
    else
        @error "Robot can not be enabled from state $(state(rob))"
    end
end

function disable(rob::Robot)
    if state(rob) == DISABLED
        return
    elseif state(rob) == READY
        _disable(rob)
        setstate!(rob, DISABLED)
    else
        @error "Robot can not be disabled from state $(state(rob))"
    end
end

function Base.reset(rob::Robot)
    _reset(rob)
    setstate!(rob, INIT)
end

function setup(rob::Robot)
    @assert state(rob) == INIT "Robot has to be in state INIT to be set up, it is currently in state $(state(rob))"
    _setup(rob)
    setstate!(rob, DISABLED)
end

function doReferenceDrive(rob::Robot)
    @assert state(rob) == READY "Robot has to be READY to perform a reference drive, it is currently in state $(state(rob))"
    setstate!(rob, MOVING)
    _doReferenceDrive(rob)
    setstate!(rob, READY)
end

function checkAxisRange(rob::Robot, coords::Vector{<:Unitful.Length})
    axes = axisRange(rob)
    inRange = true
    for i in 1:length(coords)
        inRange &= (axes[i][1] <= coords[i] <= axes[i][2])
        return inRange
    end
end

function RobotState(s::Symbol)
    reverse_dict = Dict(value => key for (key, value) in Base.Enums.namemap(RobotState))
    if s in keys(reverse_dict)
        return RobotState(reverse_dict[s])
    else
        throw(ArgumentError(string("invalid value for Enum RobotState: $s")))
    end
end


Base.convert(t::Type{RobotState}, x::Union{Symbol,Int}) = t(x)
Base.:(==)(x::RobotState, y::Union{Symbol,Int}) = try x == RobotState(y) catch ArgumentError return false end



