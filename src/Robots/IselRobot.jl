using Unitful

export IselRobot
export initZYX, refZYX, initRefZYX, simRefZYX, prepareRobot
export moveRel, moveAbs, movePark, moveCenter
export getPos, mm2Steps, steps2mm
export setZeroPoint, setBrake, setFree, setStartStopFreq, setAcceleration
export iselErrorCodes


"""Errorcodes Isel Robot """
const iselErrorCodes = Dict(
"0"=>"HandShake",
"1"=>"Error in Number, forbidden Character",
"2"=>"Endschalterfehler, NEU Initialisieren, Neu Referenzieren",
"3"=>"unzulässige Achsenzahl",
"4"=>"keine Achse definiert",
"5"=>"Syntax Fehler",
"6"=>"Speicherende",
"7"=>"unzulässige Parameterzahl",
"8"=>"zu speichernder Befehl inkorrekt",
"9"=>"Anlagenfehler",
"D"=>"unzulässige Geschwindigkeit",
"F"=>"Benutzerstop",
"G"=>"ungültiges Datenfeld",
"H"=>"Haubenbefehl",
"R"=>"Referenzfehler",
"A"=>"von dieser Steuerung nicht benutzt",
"B"=>"von dieser Steuerung nicht benutzt",
"C"=>"von dieser Steuerung nicht benutzt",
"E"=>"von dieser Steuerung nicht benutzt",
"="=>"von dieser Steuerung nicht benutzt"
)


"""
`iselRobot(portAdress::AbstractString)` e.g. `iselRobot("/dev/ttyS0")`

Initialize Isel Robot on port `portAdress`. For an overview
over the mid/high level API call `methodswith(SerialDevice{IselRobot})`.
"""
struct IselRobot <: AbstractRobot
  sd::SerialDevice
  minVel::Integer
  maxVel::Integer
  minAcc::Integer
  maxAcc::Integer
  minFreq::Integer
  maxFreq::Integer
  stepsPerTurn::Integer
  gearSlope::Integer
  stepsPermm::Float64
  defaultVel::Array{Int64,1}
  defCenterPos::Array{Int64,1}
  defParkPos::Array{Int64,1}
end

function IselRobot(portAdress::AbstractString; minVel=30, maxVel=30000,
    minAcc=1,maxAcc=4000,minFreq=20,maxFreq=4000,stepsPerTurn=5000,gearSlope=5,
    defaultVel=[10000,10000,10000],defCenterPos=[200000,100000,100000],defParkPos=[-200000,0,0],)

  pause_ms::Int = 400
  timeout_ms::Int = 40000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Integer = 19200
  ndatabits::Integer= 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1

  try
    sp = SerialPort(portAdress)
    open(sp)
    set_speed(sp, baudrate)
    return IselRobot( SerialDevice(sp,pause_ms,timeout_ms,delim_read,delim_write)
        ,minVel,maxVel,minAcc,maxAcc,minFreq,maxFreq,stepsPerTurn,gearSlope,
        stepsPerTurn / gearSlope,defaultVel,defCenterPos,defParkPos)
  catch ex
    println("Connection fail: ",ex)
  end
end

""" queryIsel(sd::SerialDevice,cmd::String) """
function queryIsel(sd::SerialDevice,cmd::String)
  flush(sd.sp)
  send(sd,string(cmd,sd.delim_write))
  i,c = LibSerialPort.sp_blocking_read(sd.sp.ref, 1, sd.timeout_ms)
  if i!=1
    error("Isel Robot did not respond!")
  end
  out = String( c )
  flush(sd.sp)
  return out
end

""" Initializes all axes in order Z,Y,X """
function initZYX(robot::IselRobot)
  ret = queryIsel(robot.sd, "@07")
  checkError(ret)
end

""" References all axes in order Z,Y,X """
function refZYX(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0R7")
  checkError(ret)
end

""" Initializes and references all axes in order Z,Y,X """
function initRefZYX(robot::IselRobot)
  initZYX(robot)
  refZYX(robot)
end

""" Move Isel Robot to center"""
function moveCenter(robot::IselRobot)
  moveAbs(robot, steps2mm(0,robot.stepsPermm),steps2mm(0,robot.stepsPermm),steps2mm(0,robot.stepsPermm))
end

""" Move Isel Robot to park"""
function movePark(robot::IselRobot)
  moveAbs(robot, steps2mm(robot.defParkPos[1],robot.stepsPermm),steps2mm(robot.defParkPos[2],robot.stepsPermm),steps2mm(robot.defParkPos[3],robot.stepsPermm));
end

function _moveRel(robot::IselRobot,stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0A"," ",stepsX,",",velX,
    ",",stepsY,",",velY,
    ",",stepsZ,",",velZ,
    ",",0,",",30)
  ret = queryIsel(robot.sd, cmd)
  checkError(ret)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveRel(robot::IselRobot,distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)
  _moveRel(robot,mm2Steps(distX,robot.stepsPermm),velX,mm2Steps(distY,robot.stepsPermm),velY,mm2Steps(distZ,robot.stepsPermm),velZ)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))` using const defaultVelocity """
function moveRel(robot::IselRobot,distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
  moveRel(robot, distX, robot.defaultVel[1],distY, robot.defaultVel[2], distZ, robot.defaultVel[3])
end

function mm2Steps(dist::typeof(1.0u"mm"),stepsPermm)
    return round(Int64,ustrip(dist)*stepsPermm)
end

function steps2mm(steps,stepsPermm)
  dist = steps/stepsPermm
  return dist*u"mm"
end

function _getPos(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P")
  checkError(ret)
  return ret
end

""" Returns Pos in mm """
function getPos(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P")
  checkError(ret)
  return parsePos(ret)
end

function parsePos(ret::AbstractString)
# 18 hex values, 6 digits per Axis order XYZ
  return ret
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

function _moveAbs(robot::IselRobot,stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0M"," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  ret = queryIsel(robot.sd, cmd)
  checkError(ret)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(robot::IselRobot,posX::typeof(1.0u"mm"), velX, posY::typeof(1.0u"mm"), velY, posZ::typeof(1.0u"mm"), velZ)
  _moveAbs(robot,mm2Steps(posX,robot.stepsPermm),velX,mm2Steps(posY,robot.stepsPermm),velY,mm2Steps(posZ,robot.stepsPermm),velZ)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(robot::IselRobot,posX::typeof(1.0u"mm"), posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  moveAbs(robot,posX,robot.defaultVel[1],posY,robot.defaultVel[2],posZ,robot.defaultVel[3])
end

""" Sets Acceleration """
function setAcceleration(robot::IselRobot,acceleration)
  ret = queryIsel(robot.sd, string("@0J",acceleration))
  checkError(ret)
end

""" Sets StartStopFrequency"""
function setStartStopFreq(robot::IselRobot,frequency)
  ret = querry(robot.sd,string("@0j",frequency))
  checkError(ret)
end

""" Sets brake, brake=false no current on brake , brake=true current on brake """
function setBrake(robot::IselRobot, brake::Bool)
  flag = brake ? 1 : 0
  ret = queryIsel(robot.sd, string("@0g",flag))
  checkError(ret)
end

""" Sets free, Freifahren axis, wenn Achse über den Referenzpunkt gefahren ist"""
function setFree(robot::IselRobot, axis)
  ret = queryIsel(robot.sd,  string("@0F",axis))
  checkError(ret)
end

""" `prepareRobot(sd::SerialDevice{IselRobot})` """
function prepareRobot(robot::IselRobot)
  # check sensor for reference
  initRefZYX(robot)
  _moveAbs(robot, robot.defCenterPos[1],robot.defaultVel[1],robot.defCenterPos[2],robot.defaultVel[2],robot.defCenterPos[3],robot.defaultVel[3])
  setZeroPoint(robot)
end

function checkError(ret::AbstractString)
  if ret != "0"
    error("Command failed: ",iselErrorCodes[ret])
  end
  return nothing
end
