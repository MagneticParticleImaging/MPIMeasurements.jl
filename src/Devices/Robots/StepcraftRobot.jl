export StepcraftRobot, StepcraftRobotParams

  #toDo: Check whether all functions can be executed in one mode: Answer No...
  #toDO: Check for differences with baby stepcraft

  #Mode 0: Transfer parameters and adjust settings
  #Mode 1: Simple movement functions for setting up the machine
  #Mode 2: Workpiece machining with speed and path control
  #Mode 3: Batch mode, runs a program with plain text commands
  #Mode 4: Speed mode for endless driving
  #Mode 9: Update and file transfer (e.g. program update)

  #Standard drive mode: MOVEMENT (1), for paramter estimation mode: PARAMETERS (0)
  #-> In mode 2 no Answers from controller when command is valid!

  @enum StepcraftMode PARAMETERS=0 MOVEMENT=1 

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
  baudrate::Int = 115200

  statusPause::typeof(1.0u"s") = 0.01u"s"

  namedPositions::Dict{String,Vector{typeof(1.0u"mm")}} = Dict("origin" => [0,0,0]u"mm")
  referenceOrder::String = "zyx"
  movementOrder::String = "zyx"
  coordinateSystem::ScannerCoordinateSystem = ScannerCoordinateSystem(3)
end
StepcraftRobotParams(dict::Dict) = params_from_dict(StepcraftRobotParams, prepareRobotDict(dict))

struct  StepcraftStatus
  idle::Bool
  hasError::Bool
  isReferenced::Bool
  onReferenceDrive::Bool
  isWaiting::Bool
end

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
  "Current Stepcraft state"
  stepcraftStatus::StepcraftStatus = StepcraftStatus(0,0,0,0,0)

end


dof(rob::StepcraftRobot) = 3
axisRange(rob::StepcraftRobot) = rob.params.axisRange # must return Vector of Vectors
defaultVelocity(rob::StepcraftRobot) = nothing # should be implemented for a robot that can handle velocities

function _setup(rob::StepcraftRobot)
  sp = LibSerialPort.open(rob.params.serial_port, rob.params.baudrate)
  rob.sd = SerialDevice(sp, rob.params.pause_ms, rob.params.timeout_ms, rob.params.delim_read, rob.params.delim_write)

  #Initilise Stepcraft Mode MOVEMENT:
  changeStepcraftMode(rob,MOVEMENT)
  updateStepcraftStatus(rob)
end

function stepcraftCommand(rob::StepcraftRobot, cmd::String)
  sd = rob.sd
  @debug "queryStepcraft: " cmd

  flush(sd.sp)
  send(sd, cmd)

  out = readuntil(rob.sd.sp,Vector{Char}("\r"),rob.params.timeout_ms)
  
  #Stepcraft responds always CR or error code with CR (except: mode 2)
  if out == ""
    error("Stepcraft robot did not respond!")
  end

  flush(sd.sp)
  return out
end

function changeStepcraftMode(rob::StepcraftRobot,mode::StepcraftMode)
  return stepcraftCommand(rob,"@M$(Int(mode))\r")
end

function updateStepcraftStatus(rob::StepcraftRobot)
  status = stepcraftCommand(rob,"@XCR")[3:4]
  rob.StepcraftStatus.idle = digits(parse(Int,status,base=16), base=2, pad=4)[1]
  rob.StepcraftStatus.hasError = digits(parse(Int,status,base=16), base=2, pad=4)[2]
  if rob.StepcraftStatus.hasError
    error("stepcraft in error state!")
  end
  rob.StepcraftStatus.isReferenced = !convert(Bool,digits(parse(Int,status,base=16), base=2, pad=4)[3])
  rob.StepcraftStatus.onReferenceDrive = digits(parse(Int,status,base=16), base=2, pad=4)[4]
end

# device specific implementations of basic functionality
function _moveAbs(rob::StepcraftRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  #[posC] = 1/1000 mm
  posSC = ustrip(pos).*1000
  V = 1 #toDO
  command = "\$E"*"$V"*",X$(posSC[1]),Y$(posSC[2]),Z$(posSC[3])"*"\r"
  out = stepcraftCommand(rob,command)
  waitForEndOfMovement(rob)
end

function _moveRel(rob::StepcraftRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  distSC = ustrip(dist).*1000
  V = 1 #toDO
  command = "\$E"*"$V"*",x$(distSC[1]),y$(distSC[2]),z$(distSC[3])"*"\r"
  out = stepcraftCommand(rob,command)
  waitForEndOfMovement(rob)
end

function waitForEndOfMovement(rob::StepcraftRobot)
  while rob.StepcraftStatus.idle
    updateStepcraftStatus(rob)
    sleep(ustrip(u"s", rob.params.statusPause))
  end
end

function _enable(rob::StepcraftRobot)
  #No relais in stepcraft
  #toDO: Stepcraft Mode?
  #out = stepcraftCommand(rob,command)
end

function _disable(rob::StepcraftRobot)
  #No relais in stepcraft
  #toDo: Wo wird das ausgeführt. Macht die Referenz kaputt...
  #out = stepcraftCommand(rob,"@S\r")
end

function _reset(rob::StepcraftRobot)
  #Untenstehender Befehl führt einen Neustart des Steuerprogramms durch. Ein Neustart ist z.B.
  #nach einem Programmupdate oder nach Änderung der Baudrate nötig.
  #Mit dem Neustart werden alle Parameter neu eingelesen.
  #toDo: Wo wird das ausgeführt. Macht die Referenz kaputt...
  #out = stepcraftCommand(rob,"@R\r")
end

function _doReferenceDrive(rob::StepcraftRobot)
  out = stepcraftCommand(rob,"\$HzxyCR")

  #Wait for end of reference drive
  while rob.StepcraftStatus.isReferenced
    updateStepcraftStatus(rob)
    sleep(ustrip(u"s", rob.params.statusPause))
  end
end

# function stepcraftStatus(rob::StepcraftRobot)
#   return stepcraftCommand(rob,"@XCR")[3:4]
# end

# function stepcraftIdleStatus(rob::StepcraftRobot)
#   status = stepcraftStatus(rob)
#   return stepcraftIdleStatus(status)
# end

# function stepcraftIdleStatus(status::AbstractString)
#   #0: stepcraft holds position, 1: stepcraft moves
#   return digits(parse(Int,status,base=16), base=2, pad=4)[1]
# end

# function stepcraftCheckError(rob::StepcraftRobot)
#   status = stepcraftStatus(rob)
#   return stepcraftCheckError(status)
# end

# function stepcraftCheckError(status::AbstractString)
#   #0: no error, 1: error
#   error = digits(parse(Int,status,base=16), base=2, pad=4)[2]
#   if error
#     error("stepcraft in error state!")
#   end
#   return error
# end

function _isReferenced(rob::StepcraftRobot)
  #status = stepcraftStatus(rob)
  #return _isReferenced(status)
  updateStepcraftStatus(rob)
  return rob.StepcraftStatus.isReferenced
end

# function _isReferenced(status::AbstractString)
#   #stepcraft returns 0 for referenced and 1 for not referenced
#   return !convert(Bool,digits(parse(Int,status,base=16), base=2, pad=4)[3])
# end

# function stepcraftBusyReferencing(rob::StepcraftRobot)
#   status = stepcraftStatus(rob)
#   return stepcraftBusyReferencing(status)
# end

# function stepcraftBusyReferencing(status::AbstractString)
#   #0: No reference drive right now, 1: stepcraft is right in the reference drive
#   return digits(parse(Int,status,base=16), base=2, pad=4)[4]
# end

function _getPosition(rob::StepcraftRobot)
  updateStepcraftStatus(rob)
  changeStepcraftMode(rob,0)

  pos = zeros(3)
  #Unit: 1/1000mm
  pos[1] = parse(Int32,stepcraftCommand(rob,"&Px\r")[5:end-1])
  pos[2] = parse(Int32,stepcraftCommand(rob,"&Py\r")[5:end-1])
  pos[3] = parse(Int32,stepcraftCommand(rob,"&Pz\r")[5:end-1])

  changeStepcraftMode(rob,1)
  
  return pos./1000*u"mm"
end