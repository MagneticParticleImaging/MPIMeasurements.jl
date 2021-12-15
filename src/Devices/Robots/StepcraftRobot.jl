export StepcraftRobot, StepcraftRobotParams

Base.@kwdef struct StepcraftRobotParams <: DeviceParams
  axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,420],[0,420],[0,420]]u"mm"
  defaultVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  defaultRefVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  invertAxes::Vector{Bool} = [false, false, false]

  minMaxVel::Vector{Int64} = [30,10000] # velocity in steps/s
  minMaxAcc::Vector{Int64} = [1,4000] # acceleration in (steps/s)/ms
  minMaxFreq::Vector{Int64} = [20,4000] # initial speed of acceleration ramp in steps/s
  stepsPermm::Float64 = 100

  serial_port::String = "/dev/ttyUSB0"
  pause_ms::Int = 200
  timeout_ms::Int = 40000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Int = 9600

  namedPositions::Dict{String,Vector{typeof(1.0u"mm")}} = Dict("origin" => [0,0,0]u"mm")
  referenceOrder::String = "zyx"
  movementOrder::String = "zyx"
  coordinateSystem::ScannerCoordinateSystem = ScannerCoordinateSystem(3)
end
StepcraftRobotParams(dict::Dict) = params_from_dict(StepcraftRobotParams, prepareRobotDict(dict))

Base.@kwdef mutable struct StepcraftRobot <: Robot
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::StepcraftRobotParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  "Current state of the robot"
  state::RobotState = INIT
  "??? for communication with the robot"
  #sd::Union{SerialDevice,Nothing} = nothing
  "State variable indicating reference status"
  isReferenced::Bool = false
  "Version of the Isel Controller 1=C142; 2=newer"
  controllerVersion::Int = 1
end


dof(rob::StepcraftRobot) = 3
@mustimplement axisRange(rob::StepcraftRobot) # must return Vector of Vectors
defaultVelocity(rob::StepcraftRobot) = nothing # should be implemented for a robot that can handle velocities

# device specific implementations of basic functionality
function _moveAbs(rob::StepcraftRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

end

function _moveRel(rob::StepcraftRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})

end

function _enable(rob::StepcraftRobot)

end

function _disable(rob::StepcraftRobot)

end

function _reset(rob::StepcraftRobot)

end

function _setup(rob::StepcraftRobot)

end

function _doReferenceDrive(rob::StepcraftRobot)

end

function _isReferenced(rob::StepcraftRobot)

end

function _getPosition(rob::StepcraftRobot)

end
