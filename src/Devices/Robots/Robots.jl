using Graphics: @mustimplement
using Unitful

export Robot, RobotState, getPosition, dof, state, isReferenced, moveAbs, moveRel, movePark, enable, disable, reset, setup, doReferenceDrive, axisRange, defaultVelocity
export teachPos, gotoPos, saveTeachedPos, namedPositions, getRobot, getRobots
export ScannerCoords, RobotCoords, getPositionScannerCoords, scannerCoordAxes, scannerCoordOrigin

@enum RobotState INIT DISABLED READY MOVING ERROR

abstract type Robot <: Device end

struct ScannerCoords{T<:Unitful.Length} <: AbstractVector{T} 
  data::Vector{T}
end

struct RobotCoords{T<:Unitful.Length} <: AbstractVector{T} 
  data::Vector{T}
end

Base.getindex(c::Union{ScannerCoords,RobotCoords}, i) = getindex(c.data, i)
Base.size(c::Union{ScannerCoords,RobotCoords}) = size(c.data)
Base.setindex!(c::Union{ScannerCoords,RobotCoords}, v, i) = setindex!(c.data,v,i)

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

function init(rob::Robot)
  @debug "Initializing robot with ID `$(rob.deviceID)`."
  setup(rob)
end

checkDependencies(rob::Robot) = true

# can be overwritten, but does not have to be
state(rob::Robot) = rob.state
setstate!(rob::Robot, state::RobotState) = rob.state = state
namedPositions(rob::Robot) = :namedPositions in fieldnames(typeof(params(rob))) ? params(rob).namedPositions : error("The parameter struct of the robot must have a field `namedPositions`.")
# should return a matrix of shape dof(rob)×dof(rob)
scannerCoordAxes(rob::Robot) = :scannerCoordAxes in fieldnames(typeof(params(rob))) ? params(rob).scannerCoordAxes : Matrix(1.0LinearAlgebra.I, dof(rob), dof(rob))
# should return a vector of shape dof(rob)
scannerCoordOrigin(rob::Robot) = :scannerCoordOrigin in fieldnames(typeof(params(rob))) ? params(rob).scannerCoordOrigin : zeros(dof(rob))*u"mm"

getRobots(scanner::MPIScanner) = getDevices(scanner, Robot)
function getRobot(scanner::MPIScanner)
  robots = getRobots(scanner)
  if length(robots) == 0
    error("The scanner has no robot.")
  elseif length(robots) > 1
    error("The scanner has more than one robot. Therefore, a robot cannot be retrieved unambiguously.")
  else
    return robots[1]
  end
end

include("RobotExceptions.jl")
include("DummyRobot.jl")
include("SimulatedRobot.jl")
include("IgusRobot.jl")
include("IselRobot.jl")
include("BrukerRobot.jl")
include("Safety.jl")
include("KnownSetups.jl")

function gotoPos(rob::Robot, pos_name::AbstractString, args...)
  if haskey(namedPositions(rob), pos_name)
    pos = namedPositions(rob)[pos_name]
    moveAbs(rob, RobotCoords(pos), args...)
  else
    throw(RobotTeachError(rob, pos_name))
  end
end

function teachPos(rob::Robot, pos_name::AbstractString; override=false)
  pos = getPosition(rob)
  if haskey(namedPositions(rob), pos_name)
    if !override
      throw(RobotTeachError(rob, pos_name))
    else
      namedPositions(rob)[pos_name] = pos
    end
  else
    push!(namedPositions(rob),pos_name=>pos)
  end
end

function saveTeachedPos(rob::Robot)
  println("To save the positions, that have been tought in the current session copy and paste the following section into the config file: ")
  println()
  println("[Devices.$(deviceID(rob)).namedPositions]")
  for (key, value) in namedPositions(rob)
    print("$(key) = [")
    for dim in value
      print("\"$(dim)\", ")
    end
    print("\033[2D") # move cursor back 2 characters (remove last comma and space)
    println("]")
  end
  println()
end

useExplicitCoordinates(rob::Robot) = ((scannerCoordAxes(rob) == LinearAlgebra.I) && (scannerCoordOrigin(rob) == zeros(dof(rob))*u"mm")) ? false : true

function toRobotCoords(rob::Robot, coords::ScannerCoords)
  rotated = inv(scannerCoordAxes(rob)) * coords.data
  return RobotCoords(rotated + scannerCoordOrigin(rob))
end

function toScannerCoords(rob::Robot, coords::RobotCoords)
  shifted = coords.data - scannerCoordOrigin(rob)
  return ScannerCoords(scannerCoordAxes(rob) * shifted)
end

moveAbs(rob::Robot, pos::Vararg{Unitful.Length,N}) where N = moveAbs(rob, [pos...])
moveAbs(rob::Robot, pos::AbstractVector{<:Unitful.Length}) = moveAbs(rob, pos, defaultVelocity(rob))
moveAbs(rob::Robot, pos::AbstractVector{<:Unitful.Length}, speed::Unitful.Velocity) = moveAbs(rob, pos, speed * ones(dof(rob)))
function moveAbs(rob::Robot, pos::AbstractVector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  if useExplicitCoordinates(rob)
    throw(RobotExplicitCoordinatesError(rob))
  else
    moveAbs(rob, RobotCoords(pos), speed)
  end
end

moveAbs(rob::Robot, pos::ScannerCoords, speed::Union{Vector{<:Unitful.Velocity},Nothing}) = moveAbs(rob, toRobotCoords(rob, pos), speed)

function moveAbs(rob::Robot, pos::RobotCoords, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  length(pos) == dof(rob) || throw(RobotDOFError(rob, length(pos)))
  state(rob) == READY || throw(RobotStateError(rob, READY))
  isReferenced(rob) || throw(RobotReferenceError(rob)) # TODO: maybe this does not have to be limited
  checkAxisRange(rob, pos) || throw(RobotAxisRangeError(rob, pos))

  #TODO: perform safety check of coordinates

  setstate!(rob, MOVING)
  try
    @debug "Started absolute robot movement to [$(join([string(x) for x in pos], ", "))] with speed $(isnothing(speed) ? speed : "["*join([string(x) for x in speed], ", ")*"]")."
    _moveAbs(rob, pos.data, speed)
    setstate!(rob, READY)
  catch exc
    setstate!(rob, ERROR)
    throw(RobotDeviceError(rob, exc))
  end
end

moveRel(rob::Robot, dist::Vararg{Unitful.Length,N}) where N = moveRel(rob, [dist...])
moveRel(rob::Robot, dist::AbstractVector{<:Unitful.Length}) = moveRel(rob, dist, defaultVelocity(rob))
moveRel(rob::Robot, dist::AbstractVector{<:Unitful.Length}, speed::Unitful.Velocity) = moveRel(rob, dist, speed * ones(dof(rob)))

function moveRel(rob::Robot, dist::AbstractVector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  if useExplicitCoordinates(rob)
    throw(RobotExplicitCoordinatesError(rob))
  else
    moveRel(rob, RobotCoords(dist), speed)
  end
end

moveRel(rob::Robot, dist::ScannerCoords, speed::Union{Vector{<:Unitful.Velocity},Nothing}) = moveRel(rob, RobotCoords(inv(scannerCoordAxes(rob)) * dist.data), speed)

function moveRel(rob::Robot, dist::RobotCoords, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  length(dist) == dof(rob) || throw(RobotDOFError(rob, length(dist)))
  state(rob) == READY || throw(RobotStateError(rob, READY))

  if isReferenced(rob)
    pos = getPosition(rob) + dist
    checkAxisRange(rob, pos) || throw(RobotAxisRangeError(rob, pos))
  else
    checkAxisRange(rob, abs.(dist)) || throw(RobotAxisRangeError(rob, dist)) #if the absolute distance in any axis is larger than the range, throw an error, however not throwing an error does not mean the movement is safe!
    @warn "Performing relative movement in unreferenced state, cannot validate coordinates! Please proceed carefully and perform only movements which are safe!"
  end

  #TODO: perform safety check of coordinates

  setstate!(rob, MOVING)

  try
    _moveRel(rob, dist.data, speed)
    setstate!(rob, READY)
  catch exc
    setstate!(rob, ERROR)
    throw(RobotDeviceError(rob, exc))
  end
end

movePark(rob::Robot) = moveAbs(rob, zeros(dof(rob)) * u"m")

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
    RobotCoords(_getPosition(rob))
  catch exc
    setstate!(rob, ERROR) # maybe it is not necessary to make this an error
    throw(RobotDeviceError(rob, exc))
  end
end

getPositionScannerCoords(rob::Robot) = toScannerCoords(rob, getPosition(rob))

function isReferenced(rob::Robot)
  try
    _isReferenced(rob)::Bool
  catch exc
    setstate!(rob, ERROR) # maybe it is not necessary to make this an error
    throw(RobotDeviceError(rob, exc))
  end
end


function checkAxisRange(rob::Robot, coords::AbstractVector{<:Unitful.Length})
  axes = axisRange(rob)
  inRange = true
  for i in 1:length(coords)
    inRange &= (axes[i][1] <= coords[i] <= axes[i][2])
  end
  return inRange
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
