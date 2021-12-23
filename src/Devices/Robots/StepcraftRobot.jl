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

  serial_port::String = "/dev/ttyUSB1"
  pause_ms::Int = 200
  timeout_ms::Int = 40000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Int = 115200

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
  sd::Union{SerialDevice,Nothing} = nothing
  "State variable indicating reference status"
  isReferenced::Bool = false
  "Version of the Isel Controller 1=C142; 2=newer"
  controllerVersion::Int = 1
end


dof(rob::StepcraftRobot) = 3
axisRange(rob::StepcraftRobot) = rob.params.axisRange # must return Vector of Vectors
defaultVelocity(rob::StepcraftRobot) = nothing # should be implemented for a robot that can handle velocities

function _setup(rob::StepcraftRobot)
  sp = LibSerialPort.open(rob.params.serial_port, rob.params.baudrate)
  rob.sd = SerialDevice(sp, rob.params.pause_ms, rob.params.timeout_ms, rob.params.delim_read, rob.params.delim_write)

  #toDo: Check whether all functions can be executed in one mode: Answer No...
  #-> In mode 2 no Answers from controller when command is valid!
  #toDO: Check for differences with baby stepcraft
  
  #Initilise Stepcraft Mode "@Mx\r":
  #Mode 0: Transfer parameters and adjust settings
  #Mode 1: Simple movement functions for setting up the machine
  #Mode 2: Workpiece machining with speed and path control
  #Mode 3: Batch mode, runs a program with plain text commands
  #Mode 4: Speed mode for endless driving
  #Mode 9: Update and file transfer (e.g. program update)
  
  #Standard dirve mode: 1, For Paramter estimation mode: 0

  stepcraftCommand(rob,"@M1\r")

end

function stepcraftCommand(rob::StepcraftRobot, cmd::String)
  sd = rob.sd
  @debug "queryStepcraft: " cmd

  flush(sd.sp)
  send(sd, cmd)

  out = readuntil(rob.sd.sp,Vector{Char}("\r"),rob.params.timeout_ms)
  
  #Stepcraft responds always CR or error code (except: mode 2)
  if out == ""
    error("Stepcraft Robot did not respond!")
  end

  flush(sd.sp)
  return out
end

function changeStepcraftMode(rob::StepcraftRobot,mode::Int)
  out = stepcraftCommand(rob,"@M$mode\r")
end

# device specific implementations of basic functionality
function _moveAbs(rob::StepcraftRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  posSC = ustrip(pos).*1000
  V = 1 #toDO
  command = "\$E"*"$V"*",X$(posSC[1]),Y$(posSC[2]),Z$(posSC[3])"*"\r"
  out = stepcraftCommand(rob,command)
end

function _moveRel(rob::StepcraftRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  posSC = ustrip(pos).*1000
  V = 1 #toDO
  command = "\$E"*"$V"*",x$(posSC[1]),y$(posSC[2]),z$(posSC[3])"*"\r"
  out = stepcraftCommand(rob,command)
end

function _enable(rob::StepcraftRobot)
  #toDO: Stecraft Mode?
  #out = stepcraftCommand(rob,command)
end

function _disable(rob::StepcraftRobot)
  #Stop?
  out = stepcraftCommand(rob,"@S\r")
end

function _reset(rob::StepcraftRobot)
  #Führt einen Neustart des Steuerprogramms durch. Ein Neustart ist z.B.
  #nach einem Programmupdate oder nach Änderung der Baudrate nötig.
  #Mit dem Neustart werden alle Parameter neu eingelesen.
  out = stepcraftCommand(rob,"@R\r")
end

function _doReferenceDrive(rob::StepcraftRobot)
  out = stepcraftCommand(rob,"\$HzxyCR")
end

function _isReferenced(rob::StepcraftRobot)
  out = stepcraftCommand(rob,"@XCR")
  
  #toDO. Check Doc
  if out == "@X00\r"
    return false
  elseif out == "@X04\r"
    return true
  else
    return true #toDO: error("Unknown Response: ", out)
  end
end

function _getPosition(rob::StepcraftRobot)
  changeStepcraftMode(rob,0)

  pos = zeros(3)
  #Unit: 1/1000mm
  pos[1] = parse(Int32,stepcraftCommand(rob,"&Px\r")[5:end-1])
  pos[2] = parse(Int32,stepcraftCommand(rob,"&Py\r")[5:end-1])
  pos[3] = parse(Int32,stepcraftCommand(rob,"&Pz\r")[5:end-1])

  changeStepcraftMode(rob,1)
  
  return pos./1000*u"mm"
end