export IselRobot, IselRobotParams
export initZYX, refZYX, initRefZYX, simRefZYX, prepareRobot
export setZeroPoint, setBrake, setFree, setStartStopFreq, setAcceleration
export iselErrorCodes
export readIOInput, writeIOOutput


"""Errorcodes Isel Robot """
const iselErrorCodes = Dict(
"0" => "HandShake",
"1" => "Error in Number, forbidden Character",
"2" => "Endschalterfehler, NEU Initialisieren, Neu Referenzieren",
"3" => "unzulässige Achsenzahl",
"4" => "keine Achse definiert",
"5" => "Syntax Fehler",
"6" => "Speicherende",
"7" => "unzulässige Parameterzahl",
"8" => "zu speichernder Befehl inkorrekt",
"9" => "Anlagenfehler",
"D" => "unzulässige Geschwindigkeit",
"F" => "Benutzerstop",
"G" => "ungültiges Datenfeld",
"H" => "Haubenbefehl",
"R" => "Referenzfehler",
"A" => "von dieser Steuerung nicht benutzt",
"B" => "von dieser Steuerung nicht benutzt",
"C" => "von dieser Steuerung nicht benutzt",
"E" => "von dieser Steuerung nicht benutzt",
"=" => "von dieser Steuerung nicht benutzt"
)

Base.@kwdef struct IselRobotParams <: DeviceParams
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

IselRobotParams(dict::Dict) = params_from_dict(IselRobotParams, prepareRobotDict(dict))

Base.@kwdef mutable struct IselRobot <: Robot
  @add_device_fields IselRobotParams

  "Current state of the robot"
  state::RobotState = INIT
  "SerialDevice for communication with the robot"
  sd::Union{SerialDevice,Nothing} = nothing
  "State variable indicating reference status"
  isReferenced::Bool = false
  "Version of the Isel Controller 1=C142; 2=newer"
  controllerVersion::Int = 1
end

abstract type IselControllerVersion end
struct IselC142 <: IselControllerVersion end
struct IseliMCS8 <: IselControllerVersion end

controllverVersion(rob::IselRobot) = rob.controllerVersion == 1 ? IselC142() : IseliMCS8()
functionUnavailable(func::AbstractString, version::IselControllerVersion) =   @error "The $func function is not available for Isel Controller version $(string(typeof(version)))"

Base.close(rob::IselRobot) = close(rob.sd.sp)

# TODO: make Isel robots with less axes possible
dof(rob::IselRobot) = 3
defaultVelocity(rob::IselRobot) = rob.params.defaultVel
axisRange(rob::IselRobot) = rob.params.axisRange
movementOrder(rob::IselRobot) = rob.params.movementOrder

function _getPosition(robot::IselRobot)
  ret = queryIsel(robot, "@0P", 19)
  checkIselError(string(ret[1]))
  pos = _parseIselPos(ret[2:19])
  return steps2mm.(pos, robot.params.stepsPermm)
end


function _setup(rob::IselRobot)
  sp = LibSerialPort.open(rob.params.serial_port, rob.params.baudrate)
  rob.sd = SerialDevice(sp, rob.params.pause_ms, rob.params.timeout_ms, rob.params.delim_read, rob.params.delim_write)

  # TODO: verify the way to identify the controller version 
  if queryIsel(rob, "@0Id 1600,1600,1600,1600") == "5"
    rob.controllerVersion = 1
  else
    rob.controllerVersion = 2
  end

  initAxes(rob, 3)
  _setup(rob, controllverVersion(rob))
end
function _setup(rob::IselRobot, version::IseliMCS8)
  invertAxes(rob, rob.params.invertAxes) # only with newer version of controller
  setRefVelocity(rob, rob.params.defaultRefVel)
end
function _setup(rob::IselRobot, version::IselC142)
  _setMotorCurrent(rob, false)
end

function _enable(robot::IselRobot)
  writeIOOutput(robot, ones(Bool, 8))
  _enable(robot, controllverVersion(robot))
end
function _enable(robot::IselRobot, version::IseliMCS8)
  # NOP
end
function _enable(robot::IselRobot, version::IselC142)
  _setMotorCurrent(robot, true)
end

function _disable(robot::IselRobot) 
  writeIOOutput(robot, zeros(Bool, 8))
  _disable(robot, controllverVersion(robot))
end
function _disable(robot::IselRobot, version::IseliMCS8)
  # NOP
end
function _disable(robot::IselRobot, version::IselC142)
  _setMotorCurrent(robot, false)
end


function prepareReferenceDrive(rob::IselRobot, version::IselC142)
  _moveRel(rob, [0.5u"mm", 0.5u"mm", 0.5u"mm"], nothing)
end
function prepareReferenceDrive(rob::IselRobot, version::IseliMCS8)
  # NOP
end

function _doReferenceDrive(rob::IselRobot)
  # Minor shift for not hitting the limit switch
  prepareReferenceDrive(rob, controllverVersion(rob))

  tempTimeout = rob.sd.timeout_ms
  try
    rob.sd.timeout_ms = 180000
    refAxis(rob, params(rob).referenceOrder[1])
    refAxis(rob, params(rob).referenceOrder[2])
    refAxis(rob, params(rob).referenceOrder[3])
  finally
    rob.sd.timeout_ms = tempTimeout
  end
  rob.isReferenced = true
end

function _isReferenced(robot::IselRobot)
  return robot.isReferenced && (robot.state != MPIMeasurements.ERROR)
  # TODO: find out if there is way to correctly identify the reference status

  #   currPos = getPosition(robot)
  #   currPos[1] += 0.01u"mm"
  # # need to add 0.01mm, otherwise moveAbs returns 0 although it is no longer referenced
  #   moveRes = _moveAbs(robot, currPos, nothing)
  #   if moveRes == "0"
  #     return true
  #   elseif moveRes == "R"
  #     return false
  #   elseif moveRes == "2"
  #     return false
  #   else
  #     error("Not expected \"$(moveRes)\" feedback from robot")
  #   end

  #   return false
end

function _reset(rob::IselRobot)
  close(rob)
  rob.isReferenced = false
end


function _moveAbs(rob::IselRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  # for z-axis two steps and velocities are needed, compare documentation
  # set second z steps to zero
  steps = mm2steps.(pos, rob.params.stepsPermm)
  if speed === nothing
    speed = defaultVelocity(rob)
  end
  vel = mm2steps.(speed, rob.params.stepsPermm)
  if all(rob.params.minMaxVel[1] .<= vel .<= rob.params.minMaxVel[2])
    cmd = string("@0M", " ", steps[1], ",", vel[1], ",", steps[2], ",", vel[2], ",", steps[3], ",", vel[3], ",", 0, ",", 30)
    ret = queryIsel(rob, cmd)
    checkIselError(ret)
  else
    error("Velocities set not in the range of $(steps2mm.(rob.params.minMaxVel, rob.params.stepsPermm)/u"s"), you are trying to set: $speed")
  end
end

function _moveRel(rob::IselRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  # for z-axis two steps and velocities are needed, compare documentation
  # set second z steps to zero
  steps = mm2steps.(dist, rob.params.stepsPermm)
  if speed === nothing
    speed = defaultVelocity(rob)
  end
  vel = mm2steps.(speed, rob.params.stepsPermm)

  if all(rob.params.minMaxVel[1] .<= vel .<= rob.params.minMaxVel[2])
    cmd = string("@0A"," ",steps[1],",",vel[1], ",",steps[2],",",vel[2], ",",steps[3],",",vel[3], ",",0,",",30)
    ret = queryIsel(rob, cmd)
    checkIselError(ret)
  else
    error("Velocities set not in the range of $(steps2mm.(rob.params.minMaxVel, rob.params.stepsPermm)/u"s"), you are trying to set: $speed")
  end
end

macro minimumISELversion(version::Int)
  return esc(quote 
    if rob.controllerVersion < $version
        @error "The desired function $(var"#self#") is not available for ISEL version $(rob.controllerVersion), the minimum version is $($version)"
        return nothing
    end
  end)
end

function _setMotorCurrent(rob::IselRobot, power::Bool)
  ret = queryIsel(rob, string("@0B65529,", Int(!power)))
  checkIselError(ret)
end

function _parseIselPos(ret::AbstractString)
  # 18 hex values, 6 digits per Axis order XYZ
  xPos = reinterpret(Int32, parse(UInt32, string("0x", ret[1:6])) << 8) >> 8
  yPos = reinterpret(Int32, parse(UInt32, string("0x", ret[7:12])) << 8) >> 8
  zPos = reinterpret(Int32, parse(UInt32, string("0x", ret[13:18])) << 8) >> 8
  return [xPos,yPos,zPos]
end

function mm2steps(len::Unitful.Length, stepsPermm::Real)
  temp = round(ustrip(u"mm", len), digits=1) # round to 100um due to step error after setting powerless
  return round(Int64, temp * stepsPermm)
end

function mm2steps(len::Unitful.Velocity, stepsPermm::Real)
  temp = round(ustrip(u"mm/s", len), digits=1) # round to 100um due to step error after setting powerless
  return round(Int64, temp * stepsPermm)
end

steps2mm(steps::Integer, stepsPermm::Real) = Int64(steps) / stepsPermm * u"mm"


""" Sets the Reference velocities of the axes x,y,z """
function setRefVelocity(rob::IselRobot, vel::Vector{<:Unitful.Velocity})
  vel = mm2steps.(vel, rob.params.stepsPermm)
  minVel = rob.params.minMaxVel[1]
  maxVel = rob.params.minMaxVel[2]

  if all(minVel .<= vel .<= maxVel)
    if rob.controllerVersion < 2
      cmd = string("@0d", vel[1], ",", vel[2], ",", vel[3], ",", vel[3])
    else
      # TODO: check if this distinction is really necessary, both should be able to use @0d
      cmd = string("@0Id", " ", vel[1], ",", vel[2], ",", vel[3], ",", vel[3])
    end
    ret = queryIsel(rob, cmd)
    checkIselError(ret)
  else
      error("Velocities set not in the range of [$minVel,$maxVel], you are trying to set vel: $vel")
  end
end


""" Initializes all axes in order Z,Y,X """
function initAxes(robot::IselRobot, numAxes::Int=3)
  if numAxes == 1
    cmd = "@01"
  elseif numAxes == 2
    cmd = "@03"
  elseif numAxes == 3
    cmd = "@07"
  else
    error("Invalid number of axes, has to be in range 1-3")
  end

  ret = queryIsel(robot, cmd)
  checkIselError(ret)
end

function refAxis(robot::IselRobot, ax::Char)
  if ax == 'x'
    cmd = "@0R1"
  elseif ax == 'y'
    cmd = "@0R2"
  elseif ax == 'z'
    cmd = "@0R4"
  else
    error("Invalid axis, has to be one of x,y,z")
  end
  ret = queryIsel(robot, cmd)
  checkIselError(ret)
end

""" Sets the zero position for absolute moving at current axes position Z,Y,X """
function setZeroPoint(robot::IselRobot)
  ret = queryIsel(robot, "@0n7")
  checkIselError(ret)
  rob.isReferenced = true
end

""" Simulates Reference Z,Y,X """
simRefZYX(robot::IselRobot, version::IselControllerVersion) = functionUnavailable("simRefZYX", version)
function simRefZYX(robot::IselRobot, version::IseliMCS8)
  ret = queryIsel(robot, "@0N7")
  checkIselError(ret)
  rob.isReferenced = true
end
function simRefZYX(robot::IselRobot)
  simRefZYX(robot, controllverVersion(robot))
end


""" Sets Acceleration """
setAcceleration(robot::IselRobot, version::IselControllerVersion, acceleration) = functionUnavailable("setAcceleration", version)
function setAcceleration(robot::IselRobot, version::IseliMCS8, acceleration)
  if robot.params.minMaxAcc[1] <= acceleration <= robot.params.minMaxAcc[2]
    ret = queryIsel(robot, string("@0J", acceleration))
    checkIselError(ret)
  else
    error("Acceleration set not in the range of $(robot.params.minMaxAcc), you are trying to set acc: $acceleration")
  end
end
function setAcceleration(robot::IselRobot, acceleration)
  setAcceleration(robot, controllverVersion(robot), acceleration)
end

""" Sets StartStopFrequency"""
setStartStopFreq(robot::IselRobot, version::IselControllerVersion, freqeuency) = functionUnavailable("setStartStopFreq", version)
function setStartStopFreq(robot::IselRobot, version::IseliMCS8, frequency)
  if robot.params.minMaxFreq[1] <= frequency <= robot.params.minMaxFreq[2]
    ret = queryIsel(robot, string("@0j", frequency))
    checkIselError(ret)
  else
    error("Frequency set not in the range of $(robot.params.minMaxFreq), you are trying to set acc: $frequency")
  end
end
function setStartStopFreq(robot::IselRobot, frequency)
  setStartStopFreq(robot, controllverVersion(robot), frequency)  
end

""" Sets brake, brake=false no current on brake , brake=true current on brake """
function setBrake(robot::IselRobot, brake::Bool)
  flag = brake ? 1 : 0
  ret = queryIsel(robot, string("@0g", flag))
  checkIselError(ret)
end

""" Sets free, Freifahren axis, wenn Achse über den Referenzpunkt gefahren ist"""
setFree(robot::IselRobot, version::IselControllerVersion, axis) = functionUnavailable("setFree", version)
function setFree(robot::IselRobot, version::IseliMCS8, axis)
  ret = queryIsel(robot,  string("@0F", axis))
  checkIselError(ret)
end
function setFree(robot::IselRobot, axis)
  setFree(robot, controllverVersion(robot), axis)
end

invertAxes(robot::IselRobot, version::IselControllerVersion, axes) = functionUnavailable("invertAxes", version)
function invertAxes(robot::IselRobot, version::IseliMCS8, axes::Array{Bool})
  num = 0
  for i in 1:dof(robot)
    num += axes[i] * 2^(i - 1)
  end
  ret = queryIsel(robot, string("@0ID", num))
  checkIselError(ret)
end
function invertAxes(robot::IselRobot, axes::Array{Bool})
  invertAxes(robot, controllverVersion(robot), axes)
end

""" Inverts the axes for y,z """
invertAxesYZ(robot::IselRobot) = invertAxes(robot, [false, true, true])

""" Inverts the axis for z """
invertAxisZ(robot::IselRobot) = invertAxes(robot, [false, false, true])
    

function checkIselError(ret::AbstractString)
  if ret != "0"
    error("Command failed: ", iselErrorCodes[ret])
  end
  return nothing
end

""" queryIsel(sd::SerialDevice,cmd::String) """
function queryIsel(rob::IselRobot, cmd::String, byteLength=1)
  sd = rob.sd
  @debug "queryIsel: " cmd

  flush(sd.sp)
  send(sd, cmd)
  i, c = LibSerialPort.sp_blocking_read(sd.sp.ref, byteLength, sd.timeout_ms)
  if i != byteLength
    error("Isel Robot did not respond!")
  end
  out = String(c)
  flush(sd.sp)
  return out
end

""" `readIOInput(robot::IselRobot)` returns an `Array{Bool,1}` of the 1-8 input slots"""
function readIOInput(robot::IselRobot)
  ret = queryIsel(robot, "@0b0", 3)
  checkIselError(string(ret[1]))
  inputBin = bin(parse(UInt8, string("0x", ret[2:3])))
  inputArray = map(x -> parse(Int64, x), collect(inputBin))
  return convert(Array{Bool,1}, inputArray)
end

""" `readIOInput(robot::IselRobot,input::Int64)` returns an Bool for the `input` slot"""
function readIOInput(robot::IselRobot, input::Int64)
  if 1 <= input && input <= 8
    return readIOInput(robot)[input]
  else
    error("input: $(input) needs to be between 1-8")
  end
end

function _writeIOOutput(robot::IselRobot, output::String)
  cmd = string("@0B0,", output)
  ret = queryIsel(robot, cmd)
  checkIselError(ret)
end

""" `writeIOOutput(robot::IselRobot,output::Array{Bool,1})` output represents 1-8 output slots"""
function writeIOOutput(robot::IselRobot, output::Array{Bool,1})
  outputInt = convert(Array{Int64,1}, output)
  outputStrings = map(x -> string(x), outputInt)
  outputBin = parse(UInt8, string("0b", string(outputStrings...)))
  _writeIOOutput(robot, string(outputBin))
end
