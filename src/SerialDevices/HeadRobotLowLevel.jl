using Unitful

export HeadRobot, headRobot
export initZYX, refZYX, initRefZYX, simRefZYX
export moveRel, moveAbs, movePark, moveCenter
export getPos
export setZeroPoint, setBrake, setFree, setStartStopFreq, setAcceleration

@compat abstract type HeadRobot <: Device end

const minVel = 30
const maxVel = 40000
const minAcceleration = 1
const maxAcceleration = 4000
const minstartStopFreq = 20
const maxstartStopFreq = 4000
const stepsPerTurn = 5000
const gearSlope = 5 # 1 turn equals 5mm feed
const stepsPermm =stepsPerTurn / gearSlope
const defaultVelocity = [1000,1000,1000]
const parkPos = [0.0,0.0,0.0]u"mm"
const centerPos = [0.0,0.0,0.0]u"mm"
const defCenterPos = [0,0,0]

"""
`headRobot(portAdress::AbstractString)` e.g. `headRobot("/dev/ttyS0")`

Initialize Head Isel Robot on port `portAdress`. For an overview
over the mid/high level API call `methodswith(SerialDevice{HeadRobot})`.
"""
function headRobot(portAdress::AbstractString)
  pause_ms::Int = 100
  timeout_ms::Int = 500
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Integer = 19200
  ndatabits::Integer= 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1

  try
    sp = SerialPort(portAdress)
    open(sp)
    return SerialDevice{HeadRobot}(sp,pause_ms,timeout_ms,delim_read,delim_write)
  catch ex
    println("Connection fail: ",ex)
  end
end

""" Initializes all axes in order Z,Y,X """
function initZYX(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@07")
  checkError(ret)
end

""" References all axes in order Z,Y,X """
function refZYX(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@0R7")
  checkError(ret)
end

""" Initializes and references all axes in order Z,Y,X """
function initRefZYX(sd::SerialDevice{HeadRobot})
  initZYX(sd)
  refZYX(sd)
end

""" Move Head Robot to center"""
function moveCenter(sd::SerialDevice{HeadRobot})
  moveAbs(sd, centerPos);
end

""" Move Head Robot to park"""
function movePark(sd::SerialDevice{HeadRobot})
  moveAbs(sd, parkPos);
end

function _moveRel(sd::SerialDevice{HeadRobot},stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0A"," ",stepsX,",",velX,
    ",",stepsY,",",velY,
    ",",stepsZ,",",velZ,
    ",",0,",",30)
  ret = querry(sd, cmd)
  checkError(ret)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)
  _moveRel(sd,mm2Steps(distX),velX,mm2Steps(distY),velY,mm2Steps(distZ),velZ)
end

""" Moves relative in mm `moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))` using const defaultVelocity """
function moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
  moveRel(sd, distX, defaultVelocity[1],distY, defaultVelocity[2], distZ, defaultVelocity[3])
end

function mm2Steps(dist::typeof(1.0u"mm"))
    return round(Int64,ustrip(dist)*stepsPermm)
end

function steps2mm(steps)
  dist = steps/stepsPermm
  return dist*u"mm"
end

function _getPos(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@0P")
  checkError(ret)
  return ret
end

""" Returns Pos in mm """
function getPos(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@0P")
  checkError(ret)
  return parsePos(ret)
end

function parsePos(ret::AbstractString)
# 18 hex values, 6 digits per Axis order XYZ
  return ret
end
""" Simulates Reference Z,Y,X """
function simRefZYX(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@0N7")
  checkError(ret)
end

""" Sets the zero position for absolute moving at current axes position Z,Y,X """
function setZeroPoint(sd::SerialDevice{HeadRobot})
  ret = querry(sd, "@0n7")
  checkError(ret)
end

function _moveAbs(sd::SerialDevice{HeadRobot},stepsX,velX,stepsY,velY,stepsZ,velZ)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0M"," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  ret = querry(sd, cmd)
  checkError(ret)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(sd::SerialDevice{HeadRobot},posX::typeof(1.0u"mm"), velX, posY::typeof(1.0u"mm"), velY, posZ::typeof(1.0u"mm"), velZ)
  _moveAbs(sd,mm2Steps(posX),velX,mm2Steps(posY),velY,mm2Steps(posZ),velZ)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{HeadRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(sd::SerialDevice{HeadRobot},posX::typeof(1.0u"mm"), posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  _moveAbs(sd,posX,defaultVelocity[1],posY,defaultVelocity[2],posZ,defaultVelocity[3])
end

""" Sets Acceleration """
function setAcceleration(sd::SerialDevice{HeadRobot},acceleration)
  ret = querry(sd, string("@0J",acceleration))
  checkError(ret)
end

""" Sets StartStopFrequency"""
function setStartStopFreq(sd::SerialDevice{HeadRobot},frequency)
  ret = querry(sd,string("@0j",frequency))
  checkError(ret)
end

""" Sets brake, brake=false no current on brake , brake=true current on brake """
function setBrake(sd::SerialDevice{HeadRobot}, brake::Bool)
  flag= brake ? 1 : 0
  ret = querry(sd, string("@0g",flag))
  checkError(ret)
end

""" Sets free, Freifahren axis, wenn Achse über den Referenzpunkt gefahren ist"""
function setFree(sd::SerialDevice{HeadRobot}, axis)
  ret = querry(sd,  string("@0F",axis))
  checkError(ret)
end

""" `prepareRobot(sd::SerialDevice{HeadRobot})` """
function prepareRobot(sd::SerialDevice{HeadRobot})
  # check sensor for reference
  initRefZYX(sd)
  moveAbs(sd, defCenterPos[1],defaultVelocity[1],defCenterPos[2],defaultVelocity[2],defCenterPos[3],defaultVelocity[3])
  setZeroPoint(sd)
end

function checkError(ret::AbstractString)
  if ret != "0"
    error("Command failed: ",iselErrorCodes[ret])
  end
  return nothing
end
