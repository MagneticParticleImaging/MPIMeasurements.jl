using Graphics: @mustimplement
using Unitful

export Robot, RobotState, getPosition, dof, state, isReferenced, moveAbs, moveRel, enable, disable, reset, setup, doReferenceDrive, axisRange, defaultVelocity

@enum RobotState INIT DISABLED READY MOVING ERROR

abstract type Robot <: Device end

# general interface functions to be implemented by devices
@mustimplement dof(rob::Robot)
@mustimplement axisRange(rob::Robot) # must return Vector of Vectors
defaultVelocity(rob::Robot) = nothing # should be implemented for a robot that can handle velocities

# device specific implementations of basic functionality
@mustimplement _moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
@mustimplement _moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
@mustimplement _enable(rob::Robot)
@mustimplement _disable(rob::Robot)
@mustimplement _reset(rob::Robot)
@mustimplement _setup(rob::Robot)
@mustimplement _doReferenceDrive(rob::Robot)
@mustimplement _isReferenced(rob::Robot)
@mustimplement _getPosition(rob::Robot)

# can be overwritten, but does not have to be
state(rob::Robot) = rob.state
setstate!(rob::Robot, state::RobotState) = rob.state = state

include("RobotExceptions.jl")
include("DummyRobot.jl")
include("SimulatedRobot.jl")
include("IgusRobot.jl")
include("IselRobot.jl")
include("BrukerRobot.jl")
include("Safety.jl")
include("KnownSetups.jl")

moveAbs(rob::Robot, pos::Vararg{Unitful.Length,N}) where N = moveAbs(rob, [pos...])
moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}) = moveAbs(rob, pos, defaultVelocity(rob))
moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Unitful.Velocity) = moveAbs(rob, pos, speed * ones(dof(rob)))

function moveAbs(rob::Robot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

    length(pos) == dof(rob) || throw(RobotDOFError(rob, length(pos)))
    state(rob) == READY || throw(RobotStateError(rob, READY))
    isReferenced(rob) || throw(RobotReferenceError(rob)) # TODO: maybe this does not have to be limited
    checkAxisRange(rob, pos) || throw(RobotAxisRangeError(rob, pos))
    
    #TODO: perform safety check of coordinates

    setstate!(rob, MOVING)
    try
        @debug "Started absolute robot movement to $pos with $speed."
        _moveAbs(rob, pos, speed)
        setstate!(rob, READY)
    catch exc
        setstate!(rob, ERROR)
        throw(RobotDeviceError(rob, exc))
    end
end

moveRel(rob::Robot, dist::Vararg{Unitful.Length,N}) where N = moveRel(rob, [dist...])
moveRel(rob::Robot, dist::Vector{<:Unitful.Length}) = moveRel(rob, dist, defaultVelocity(rob))
moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Unitful.Velocity) = moveRel(rob, dist, speed * ones(dof(rob)))

function moveRel(rob::Robot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

    length(dist) == dof(rob) || throw(RobotDOFError(rob, length(dist)))
    state(rob) == READY || throw(RobotStateError(rob, READY))
    
    pos = getPosition(rob) + dist
    checkAxisRange(rob, pos) || throw(RobotAxisRangeError(rob, pos))
    
    #TODO: perform safety check of coordinates
    
    setstate!(rob, MOVING)
    
    try
        _moveRel(rob, dist, speed)
        setstate!(rob, READY)
    catch exc
        setstate!(rob, ERROR)
        throw(RobotDeviceError(rob, exc))        
    end
end

function enable(rob::Robot)
    if state(rob) == READY
        return READY
    elseif state(rob) == DISABLED
        try
            _enable(rob)
            setstate!(rob, READY)
        catch exc
            setstate!(rob, ERROR)
            throw(RobotDeviceError(rob, exc))
        end
    else
        throw(RobotStateError(rob, DISABLED))
    end
end

function disable(rob::Robot)
    if state(rob) == DISABLED
        return DISABLED
    elseif state(rob) == READY
        try
            _disable(rob)
            setstate!(rob, DISABLED)
        catch exc
            setstate!(rob, ERROR)
            throw(RobotDeviceError(rob, exc))
        end
    else
        throw(RobotStateError(rob, READY))
    end
end

function Base.reset(rob::Robot)
    try
        _reset(rob)
        setstate!(rob, INIT)
    catch exc
        setstate!(rob, ERROR)
        throw(RobotDeviceError(rob, exc))
    end
end

function setup(rob::Robot)
    state(rob) == INIT || throw(RobotStateError(rob, INIT))
    try
        _setup(rob)
    catch exc
        setstate!(rob, ERROR)
        throw(RobotDeviceError(rob, exc))
    end
    setstate!(rob, DISABLED)
end

function doReferenceDrive(rob::Robot)
    state(rob) == READY || throw(RobotStateError(rob, READY))
    try
        setstate!(rob, MOVING)
        _doReferenceDrive(rob)
        setstate!(rob, READY)
    catch exc
        setstate!(rob, ERROR)
        throw(RobotDeviceError(rob, exc))
    end
end

function getPosition(rob::Robot)
    try
        _getPosition(rob)
    catch exc
        setstate!(rob, ERROR) # maybe it is not necessary to make this an error
        throw(RobotDeviceError(rob, exc))
    end
end

function isReferenced(rob::Robot)
    try
        _isReferenced(rob)::Bool
    catch exc
        setstate!(rob, ERROR) # maybe it is not necessary to make this an error
        throw(RobotDeviceError(rob, exc))
    end
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
Base.:(==)(x::RobotState, y::Union{Symbol,Int}) = try x == RobotState(y) catch _ return false end


