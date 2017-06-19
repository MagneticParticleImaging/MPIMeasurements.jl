using Unitful

export initRefZYX, moveRel, moveAbs,setZeroPoint, setBrake, setFree

const minVel = 30
const maxVel = 40000
const minAcceleration = 1
const maxAcceleration = 4000
const minstartStopFreq = 20
const maxstartStopFreq = 4000
const stepsPerTurn = 5000
const gearSlope = 5 # 1 turn equals 5mm feed
const stepsPermm =stepsPerTurn / gearSlope

function addCR(cmd::String)
    return string(cmd,"\r")
end


function initZYX()
  c="@07"
  return addCR(c)
end

function refZYX()
  c="@0R7"
  return addCR(c)
end

function initRefZYX()
  cmds = Array{String,1}(2)
  cmds[1] = initZYX()
  cmds[2] = refZYX()
  return cmds
end

function _moveRel(stepsX,velX,stepsY,velY,stepsZ,velZ)
  c="@0A"
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string(c," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  return addCR(cmd)
end

function moveRel(distX::typeof(1.0u"mm"), velX, distY::typeof(1.0u"mm"), velY, distZ::typeof(1.0u"mm"), velZ)
  return _moveRel(mm2Steps(distX),velX,mm2Steps(distY),velY,mm2Steps(distZ),velZ)
end

function mm2Steps(dist::typeof(1.0u"mm"))
    return round(Int64,ustrip(dist)*stepsPermm)
end

function getPos()
  c="@0P"
  return addCR(c)
end

function parsePos()
# 18 hex values, 6 digits per Axis order XYZ
end

function simRefZYX()
  c="@0N7"
  return addCR(c)
end

function setZeroPoint()
  c="@0n7" # for absolute move
  return addCR(c)
end

function _moveAbs(stepsX,velX,stepsY,velY,stepsZ,velZ)
  c="@0M"
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string(c," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  return addCR(cmd)
end

function moveAbs(posX::typeof(1.0u"mm"), velX, posY::typeof(1.0u"mm"), velY, posZ::typeof(1.0u"mm"), velZ)
  return _moveAbs(mm2Steps(posX),velX,mm2Steps(posY),velY,mm2Steps(posZ),velZ)
end

function setAcceleration(acceleration)
  c="@0J"
  cmd=string(c,acceleration)
  return addCR(cmd)
end

function setStartStopFreq(frequency)
  c="@0j"
  cmd=string(c,frequency)
  return addCR(cmd)
end

""" flag=0 no current on brake , flag=1 current on brake """
function setBrake(flag)
  c="@0g"
  cmd=string(c,flag)
  return addCR(cmd)
end

""" Freifahren axis, wenn achse über den Referenzpunkt gefahren ist"""
function setFree(axis)
  c="@0F"
  cmd=string(c,axis)
  return addCR(cmd)
end
