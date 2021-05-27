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
  axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[0,500],[0,500],[0,500]]u"mm"
  defaultVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"
  defaultRefVel::Vector{typeof(1.0u"mm/s")} = [10,10,10]u"mm/s"

  minMaxVel::Vector{Int64} = [0,1]
  minMaxAcc::Vector{Int64} = [0,1]
  minMaxFreq::Vector{Int64} = [0,1]
  stepsPermm::Float64 = 100
  
  serial_port::String = "COM4"
  pause_ms::Int = 200
  timeout_ms::Int = 40000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Int = 19200
end

mutable struct IselRobot <: Robot
  deviceID::String
  params::IselRobotParams
  state::RobotState
  sd::Union{SerialDevice,Nothing}
  IselRobot(deviceID::String, params::IselRobotParams)= new(deviceID, params, INIT, nothing)
end

Base.close(rob::IselRobot) = close(rob.sd.sp)

dof(rob::IselRobot) = 3
defaultVelocity(rob::IselRobot) = rob.params.defaultVel
axisRange(rob::IselRobot) = rob.params.axisRange

function _getPosition(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P", 19)
  checkError(string(ret[1]))
  pos = parsePos(ret[2:19])
  return steps2mm.(pos, robot.params.stepsPermm)
end


function _setup(rob::IselRobot)
  sp = SerialPort(rob.params.serial_port)
  open(sp)
  set_speed(sp, rob.params.baudrate)
  rob.sd = SerialDevice(sp, pause_ms, timeout_ms, delim_read, delim_write)

  # invertAxesYZ(iselRobot)
  invertAxisZ(rob)
  initZYX(rob)
  setRefVelocity(rob, rob.params.defaultRefVel)
end

_enable(robot::IselRobot) = writeIOOutput(robot, ones(Bool, 8))
_disable(robot::IselRobot) = writeIOOutput(robot, zeros(Bool, 8))    

function _doReferenceDrive(rob::IselRobot)
  # check sensor for reference
  tempTimeout = robot.sd.timeout_ms
  try
    rob.sd.timeout_ms = 180000
    refZYX(rob)
  finally
    rob.sd.timeout_ms = tempTimeout
  end
end

function _isReferenced(robot::IselRobot)
  currPos = getPosition(robot)
  currPos[1] += 0.01u"mm"
# need to add 0.01mm, otherwise moveAbs returns 0 although it is no longer referenced
  moveRes = _moveAbs(robot, currPos, nothing)
  if moveRes == "0"
    return true
  elseif moveRes == "R"
    return false
  elseif moveRes == "2"
    return false
  else
    error("Not expected \"$(moveRes)\" feedback from robot")
  end

  return false
end


function _moveAbs(rob::IselRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
    steps = mm2steps.(pos, rob.params.stepsPermm)
    if speed === nothing
        speed = defaultVelocity(rob)
    end
  # ?? vel = mm2steps(speed) ??
    cmd = string("@0M", " ", steps[1], ",", vel[1], ",", steps[2], ",", vel[2], ",", steps[3], ",", vel[3], ",", 0, ",", 30)
    ret = queryIsel(rob.sd, cmd)
    checkError(ret)
end

function _moveRel(rob::IselRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
    steps = mm2steps.(dist, rob.params.stepsPermm)
    if speed === nothing
        speed = defaultVelocity(rob)
    end
  # ?? vel = mm2steps(speed) ??
    cmd = string("@0A"," ",steps[1],",",vel[1],
    ",",steps[2],",",vel[2],
    ",",steps[3],",",vel[3],
    ",",0,",",30)
    ret = queryIsel(rob.sd, cmd)
    checkError(ret)
end

function parsePos(ret::AbstractString)
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

steps2mm(steps::Int, stepsPermm::Real) = steps / stepsPermm * u"mm"


""" Sets the Reference velocities of the axes x,y,z """
function setRefVelocity(rob::IselRobot, vel::Vector{Int64})
  minVel = rob.params.minMaxVel[1]
  maxVel = rob.params.minMaxVel[2]

  if minVel <= vel[1] && vel[1] <= maxVel && minVel <= vel[2] && vel[2] <= maxVel &&
      minVel <= vel[3] && vel[3] <= maxVel
    cmd = string("@0Id", " ", vel[1], ",", vel[2], ",", vel[3], ",", vel[3])
    ret = queryIsel(rob.sd, cmd)
    checkError(ret)
  else
      error("Velocities set not in the range of [$minVel,$maxVel], you are trying to set vel: $vel")
  end
end


""" Initializes all axes in order Z,Y,X """
function initZYX(robot::IselRobot)
    ret = queryIsel(robot.sd, "@07")
    checkError(ret)
end

""" References all axes in order Z,Y,X """
function refZYX(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0R1")
    checkError(ret)
    ret = queryIsel(robot.sd, "@0R4")
    checkError(ret)
    ret = queryIsel(robot.sd, "@0R2")
    checkError(ret)
end

""" Simulates Reference Z,Y,X """
function simRefZYX(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0N7")
    checkError(ret)
end




""" Sets the zero position for absolute moving at current axes position Z,Y,X """
function setZeroPoint(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0n7")
    checkError(ret)
end

""" Sets Acceleration """
function setAcceleration(robot::IselRobot, acceleration)
  if robot.params.minMaxAcc[1]<=acceleration<=robot.params.minMaxAcc[2]
      ret = queryIsel(robot.sd, string("@0J", acceleration))
      checkError(ret)
  else
    error("Acceleration set not in the range of $(robot.params.minMaxAcc), you are trying to set acc: $acceleration")
  end
end

""" Sets StartStopFrequency"""
function setStartStopFreq(robot::IselRobot, frequency)
  if robot.params.minMaxFreq[1]<=frequency<=robot.params.minMaxFreq[2]
    ret = queryIsel(robot.sd, string("@0j", frequency))
    checkError(ret)
  else
    error("Frequency set not in the range of $(robot.params.minMaxFreq), you are trying to set acc: $frequency")
  end   
end

""" Sets brake, brake=false no current on brake , brake=true current on brake """
function setBrake(robot::IselRobot, brake::Bool)
  flag = brake ? 1 : 0
  ret = queryIsel(robot.sd, string("@0g", flag))
  checkError(ret)
end

""" Sets free, Freifahren axis, wenn Achse über den Referenzpunkt gefahren ist"""
function setFree(robot::IselRobot, axis)
  ret = queryIsel(robot.sd,  string("@0F", axis))
  checkError(ret)
end

""" Inverts the axes for y,z """
function invertAxesYZ(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0ID6")
    checkError(ret)
end

""" Inverts the axis for z """
function invertAxisZ(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0ID4")
    checkError(ret)
end

function checkError(ret::AbstractString)
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
  send(sd, string(cmd, sd.delim_write))
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
    ret = queryIsel(robot.sd, "@0b0", 3)
    checkError(string(ret[1]))
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
    ret = queryIsel(robot.sd, cmd)
    checkError(ret)
end

""" `writeIOOutput(robot::IselRobot,output::Array{Bool,1})` output represents 1-8 output slots"""
function writeIOOutput(robot::IselRobot, output::Array{Bool,1})
    outputInt = convert(Array{Int64,1}, output)
    outputStrings = map(x -> string(x), outputInt)
    outputBin = parse(UInt8, string("0b", string(outputStrings...)))
    _writeIOOutput(robot, string(outputBin))
end
