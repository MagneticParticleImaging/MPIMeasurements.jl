export StepcraftRobot, StepcraftRobotParams

  #toDo: Check whether all functions can be executed in one mode: Answer No...

  #Mode 0: Transfer parameters and adjust settings
  #Mode 1: Simple movement functions for setting up the machine
  #Mode 2: Workpiece machining with speed and path control
  #Mode 3: Batch mode, runs a program with plain text commands
  #Mode 4: Speed mode for endless driving
  #Mode 9: Update and file transfer (e.g. program update)

  #Standard drive mode: MOVEMENT (1), for paramter estimation mode: PARAMETERS (0)
  #-> In mode 2 no Answers from controller when command is valid!

  #Attention! Emergency stop does not lead to an error state!

@enum StepcraftMode PARAMETERS=0 MOVEMENT=1 

Base.@kwdef struct StepcraftRobotParams <: DeviceParams
  axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,420],[0,420],[0,420]]u"mm"
  defaultVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  defaultRefVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  invertRefAxes::Vector{Bool}
  invertAxes::Vector{Bool} = [false, false, false]

  minMaxVel::Vector{Int64} = [30,10000] # velocity in steps/s, toDo
  minMaxAcc::Vector{Int64} = [1,4000] # acceleration in (steps/s)/ms, toDo
  minMaxFreq::Vector{Int64} = [20,4000] # initial speed of acceleration ramp in steps/s, toDo
  stepsPerRotation::Float64 = 400
  distancePerRotation::typeof(1u"mm") = 3u"mm"

  serial_port::String = "/dev/ttyUSB0"
  pause_ms::Int = 200
  timeout_ms::Int = 4000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Int = 115200

  statusPause::typeof(1.0u"s") = 0.01u"s"
  statusTimeout::typeof(1.0u"s") = 60u"s"

  namedPositions::Dict{String,Vector{typeof(1.0u"mm")}} = Dict("origin" => [0,0,0]u"mm")
  referenceOrder::String = "zyx"
  movementOrder::String = "zyx"
  coordinateSystem::ScannerCoordinateSystem = ScannerCoordinateSystem(3)
end
StepcraftRobotParams(dict::Dict) = params_from_dict(StepcraftRobotParams, prepareRobotDict(dict))

mutable struct StepcraftStatus
  idle::Bool
  hasError::Bool
  isReferenced::Bool
  onReferenceDrive::Bool
  isWaiting::Bool
end

Base.@kwdef mutable struct StepcraftRobot <: Robot
  @add_device_fields StepcraftRobotParams

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
  "Current Speed"
  vel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
end


dof(rob::StepcraftRobot) = 3
axisRange(rob::StepcraftRobot) = rob.params.axisRange # must return Vector of Vectors
defaultVelocity(rob::StepcraftRobot) = rob.params.defaultVel # should be implemented for a robot that can handle velocities

function _setup(rob::StepcraftRobot)
  rob.sd = SerialDevice(rob.params.serial_port; baudrate = rob.params.baudrate, delim_read = rob.params.delim_read, delim_write = rob.params.delim_write, timeout_ms = rob.params.timeout_ms)
  set_flow_control(rob.sd.sp, xonxoff=SP_XONXOFF_INOUT) # TODO COMMENT WHY

  stopStepcraftSpam(rob)
  setSpindel(rob)
  initSpeed(rob)
  invertAxes(rob)
  setStepcraftMode(rob,MOVEMENT)
  updateStepcraftStatus(rob)
  if rob.stepcraftStatus.hasError
    error("stepcraft in error state!")
  end
end

function stopStepcraftSpam(rob::StepcraftRobot)
  #Getting rid of the stepcraft spam. The following stepcraft command is not in the manual but deactivates the serial position monitoring during movements:
  setStepcraftMode(rob,PARAMETERS)
  stepcraftCommand(rob,"#C52,0")
  setStepcraftMode(rob,MOVEMENT)
end

function setSpindel(rob::StepcraftRobot)
  setStepcraftMode(rob,PARAMETERS)

  stepsPerRotation = rob.params.stepsPerRotation
  distancePerRotation = Int(round(ustrip(rob.params.distancePerRotation*1000)))
  stepcraftCommand(rob,"#Zx,$(stepsPerRotation)")
  stepcraftCommand(rob,"#Zy,$(stepsPerRotation)")
  stepcraftCommand(rob,"#Zz,$(stepsPerRotation)")
  stepcraftCommand(rob,"#Nx,$(distancePerRotation)")
  stepcraftCommand(rob,"#Ny,$(distancePerRotation)")
  stepcraftCommand(rob,"#Nz,$(distancePerRotation)")

  setStepcraftMode(rob,MOVEMENT)
end

function initSpeed(rob::StepcraftRobot)
  setStepcraftMode(rob,PARAMETERS)

  #For normal drive
  vel = ustrip(uconvert.(u"µm/s",rob.params.defaultVel))
  stepcraftCommand(rob,"#G1,$(Int(round(minimum(vel))))")
  stepcraftCommand(rob,"#G2,$(Int(round(maximum(vel))))")
  stepcraftCommand(rob,"#G3,$(Int(round(vel[1])))")
  stepcraftCommand(rob,"#G4,$(Int(round(vel[2])))")
  stepcraftCommand(rob,"#G5,$(Int(round(vel[3])))")

  rob.vel = rob.params.defaultVel
  
  #For reference drive, also sets axes inversion
  refVel = ustrip(uconvert.(u"µm/s",rob.params.defaultRefVel))
  axes = rob.params.invertRefAxes
  stepcraftCommand(rob,"#G6,$(Int(round(minimum(refVel))))")
  stepcraftCommand(rob,"#DX,$(convert(Int, axes[1])),6,6,6")
  stepcraftCommand(rob,"#DY,$(convert(Int, axes[2])),6,6,6")
  stepcraftCommand(rob,"#DZ,$(convert(Int, axes[3])),6,6,6")

  setStepcraftMode(rob,MOVEMENT)
end

function invertAxes(rob::StepcraftRobot)
  setStepcraftMode(rob,PARAMETERS)
  axes = rob.params.invertAxes
  defaultRefVel = ustrip(uconvert.(u"µm/s",rob.params.defaultRefVel))
  setStepcraftMode(rob,PARAMETERS)

  #For normal drive:
  stepcraftCommand(rob,"#Yx,$(convert(Int,axes[1]))")
  stepcraftCommand(rob,"#Yy,$(convert(Int,axes[2]))")
  stepcraftCommand(rob,"#Yz,$(convert(Int,axes[3]))")

  setStepcraftMode(rob,MOVEMENT)
end

function stepcraftCommand(rob::StepcraftRobot, cmd::String)
  return query(rob.sd, cmd)
end

function setSpeed(rob::StepcraftRobot,speed::Vector{<:Unitful.Velocity})
  #There are 100 memory locations to store velocities. We use only the first six and 
  #update it as soon as a new velocity is set. On entry 6 the velocitiy during 
  #the search run, the free run from the switch and the subsequent optional offset 
  #run for the reference drive is stored and not changed during operation.
  #toDo: consider brake angle
  #Problem: the stepcraft command for abs und rel movements can only handle one velocity entry for all three axis.
  #Oberservation: all axis are moving simultaneously and the movement ends at the same time.
  #Assumption: the passed velocity is the maximal velocity which is the vel of the axis with the longest distance to move.
  #All other axis getting smaller velocities such that all movements end at the same time. No doc found...
  #It would be possible to drive the axes one after the other, but this would only cost additional time.

  setStepcraftMode(rob,PARAMETERS)
  
  if (speed != rob.vel)
    #Set new velocities
    speedRob = ustrip(uconvert.(u"µm/s",speed))
    stepcraftCommand(rob,"#G1,$(Int(round(minimum(speedRob))))")
    stepcraftCommand(rob,"#G2,$(Int(round(maximum(speedRob))))")
    stepcraftCommand(rob,"#G3,$(Int(round(speedRob[1])))")
    stepcraftCommand(rob,"#G4,$(Int(round(speedRob[2])))")
    stepcraftCommand(rob,"#G5,$(Int(round(speedRob[3])))")
    rob.vel = speed
  end

  setStepcraftMode(rob,MOVEMENT)
end

function setSpeed(rob::StepcraftRobot, speed::Nothing)
  # NOP
end

function setStepcraftMode(rob::StepcraftRobot,mode::StepcraftMode)
  return stepcraftCommand(rob,"@M$(Int(mode))")
end

function updateStepcraftStatus(rob::StepcraftRobot)
  #Don't trust hasError and onReferenceDrive. toDo: trustworthy error
  preStatus = stepcraftCommand(rob,"@X")
  index = findfirst('X', preStatus)
  status = preStatus[index+1:index+2]
  
  rob.stepcraftStatus.idle = 1 - parse(Bool,status[1])
  rob.stepcraftStatus.hasError = (parse(Int,status[2],base=16) >> 1) & 1
  rob.stepcraftStatus.isReferenced = (parse(Int,status[2],base=16) >> 2) & 1
  rob.stepcraftStatus.onReferenceDrive = (parse(Int,status[2],base=16) >> 3) & 1
end

# device specific implementations of basic functionality
function _moveAbs(rob::StepcraftRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  #[posC] = µm
  posSC = ustrip(pos).*1000
  setSpeed(rob,speed)
  #robot moves with minimal velocity of speed...
  command = "\$E1,X$(posSC[1]),Y$(posSC[2]),Z$(posSC[3])"
  out = stepcraftCommand(rob,command)
  #catchingStepcraftSpam(rob)
  waitForStatus(rob,:idle,false)
end

function _moveRel(rob::StepcraftRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  distSC = ustrip(uconvert.(u"µm",dist))
  setSpeed(rob,speed)
  #robot moves with minimal velocity of speed...
  command = "\$E1,x$(distSC[1]),y$(distSC[2]),z$(distSC[3])"
  out = stepcraftCommand(rob,command)
  #@info "bla"*out*"foo"
  #catchingStepcraftSpam(rob)
  waitForStatus(rob,:idle,false)
end

#function catchingStepcraftSpam(rob::StepcraftRobot)
#  #Hack(-elberg) to get rid of the position data sended during movements... 
#  reply = readuntil(rob.sd.sp, Vector{Char}("\r"), 500)
#  while reply != ""
#    reply = readuntil(rob.sd.sp, Vector{Char}("\r"), 500)
#    println(reply)#*string(length(bla)))
#    #updateStepcraftStatus(rob)
#  end
#end

function waitForStatus(rob::StepcraftRobot, status::Symbol, inverted::Bool=false)
  updateStepcraftStatus(rob)

  timeout = ustrip(u"s", rob.params.statusTimeout)
  t0 = time()

	while getfield(rob.stepcraftStatus, status) == inverted
		updateStepcraftStatus(rob)
		if rob.stepcraftStatus.hasError && status != :hasError
			error("Stepcraft in error state!")
		end

    # check timeout
    if(time()-t0 > timeout)
      error("Stepcraft timeout while waiting for status to change.")
    end

    sleep(ustrip(u"s", rob.params.statusPause))
	end
end

function waitForEndOfMovement(rob::StepcraftRobot)
  while rob.stepcraftStatus.idle
    updateStepcraftStatus(rob)
    sleep(ustrip(u"s", rob.params.statusPause))
  end
end

function _enable(rob::StepcraftRobot)
  #No relais in stepcraft
end

function _disable(rob::StepcraftRobot)
  #No relais in stepcraft
end

function _reset(rob::StepcraftRobot)
  #Untenstehender Befehl führt einen Neustart des Steuerprogramms durch. Ein Neustart ist z.B.
  #nach einem Programmupdate oder nach Änderung der Baudrate nötig.
  #Mit dem Neustart werden alle Parameter neu eingelesen.
  #toDo: Wo wird das ausgeführt. Macht die Referenz kaputt...
  #out = stepcraftCommand(rob,"@R\r")
end

function _doReferenceDrive(rob::StepcraftRobot) #toDO: Prevent endless loop when emergency stop is pressed during reference drive.
  out = stepcraftCommand(rob,"\$H"*rob.params.referenceOrder)
  #catchingStepcraftSpam(rob)
  waitForStatus(rob,:isReferenced,false)
end

function _isReferenced(rob::StepcraftRobot)
  updateStepcraftStatus(rob)
  return rob.stepcraftStatus.isReferenced
end

function _getPosition(rob::StepcraftRobot)
  updateStepcraftStatus(rob)

  setStepcraftMode(rob,PARAMETERS)
  sleep(0.1)
  pos = zeros(3)
  #Unit: µm
  pos[1] = parse(Int32,stepcraftCommand(rob,"&Px")[5:end])
  pos[2] = parse(Int32,stepcraftCommand(rob,"&Py")[5:end])
  pos[3] = parse(Int32,stepcraftCommand(rob,"&Pz")[5:end])

  setStepcraftMode(rob,MOVEMENT)
  
  return pos./1000*u"mm"
end

Base.close(rob::StepcraftRobot) = close(rob.sd)