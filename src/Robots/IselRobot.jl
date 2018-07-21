using Unitful

export IselRobot
export initZYX, refZYX, initRefZYX, simRefZYX, prepareRobot
export moveRel, moveAbs, movePark, moveCenter, moveSampleCenterPos
export getPos, mm2Steps, steps2mm
export setZeroPoint, setBrake, setFree, setStartStopFreq, setAcceleration
export iselErrorCodes
export saveTeachPosition, TeachPosition
export readIOInput, writeIOOutput


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
struct IselRobot <: Robot
  sd::SerialDevice
  minMaxVel::Array{Int64,1}
  minMaxAcc::Array{Int64,1}
  minMaxFreq::Array{Int64,1}
  stepsPerTurn::Integer
  gearSlope::Integer
  stepsPermm::Float64
  defaultVel::Array{Int64,1}
  defCenterPos::Array{typeof(1.0u"mm"),1}
  defSampleCenterPos::Array{typeof(1.0u"mm"),1}
  defParkPos::Array{typeof(1.0u"mm"),1}
end

function IselRobot(params::Dict)
  pause_ms::Int = 400
  timeout_ms::Int = 40000
  delim_read::String = "\r"
  delim_write::String = "\r"
  baudrate::Integer = 19200
  ndatabits::Integer= 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1
  stepsPermm = params["stepsPerTurn"] / params["gearSlope"]
  defCenterPos = map(x->uconvert(u"mm",x), params["defCenterPos"]*u"m")
  defSampleCenterPos = map(x->uconvert(u"mm",x), params["defSampleCenterPos"]*u"m")
  defParkPos = map(x->uconvert(u"mm",x),params["defParkPos"]*u"m")
  defParkPos[1] = defParkPos[1] - defCenterPos[1] # maxX 420mm minus current teaching Pos = new Park Pos
  try
    sp = SerialPort(params["connection"])
    open(sp)
    set_speed(sp, baudrate)
    iselRobot = IselRobot( SerialDevice(sp,pause_ms,timeout_ms,delim_read,delim_write)
        ,params["minMaxVel"],params["minMaxAcc"],params["minMaxFreq"],params["stepsPerTurn"],params["gearSlope"],
        stepsPermm,params["defaultVel"],defCenterPos,defSampleCenterPos, defParkPos)
    invertAxesYZ(iselRobot)
    initZYX(iselRobot)
    setVelocity(iselRobot,iselRobot.defaultVel[1],iselRobot.defaultVel[2],iselRobot.defaultVel[3])
    # check whether robot has been referenced or needs to be referenced
    if !haskey(params,"doReferenceCheck") || params["doReferenceCheck"]
      referenced = isReferenced(iselRobot)
      if !referenced
        userGuidedPreparation(iselRobot)
      end
    end
    return iselRobot
  catch ex
    println("Connection fail: ",ex)
  end
end

parkPos(robot::IselRobot) = robot.defParkPos

function isReferenced(robot::IselRobot)
  currPos = getPos(robot)
  # need to add 0.01u"mm", otherwise moveAbs returns 0 although it is no longer referenced
  moveRes = moveAbs(robot,currPos[1]+0.01u"mm", currPos[2], currPos[3],false)
  if moveRes=="0"
    return true
  elseif moveRes=="R"
    return false
  elseif moveRes=="2"
    return false
  else
      error("Not expected \"$(moveRes)\" feedback from robot")
  end
  return false
end

""" queryIsel(sd::SerialDevice,cmd::String) """
function queryIsel(sd::SerialDevice,cmd::String, byteLength=1)
  flush(sd.sp)
  send(sd,string(cmd,sd.delim_write))
  i,c = LibSerialPort.sp_blocking_read(sd.sp.ref, byteLength, sd.timeout_ms)
  if i!=byteLength
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
  ret = queryIsel(robot.sd, "@0R1")
  checkError(ret)
  ret = queryIsel(robot.sd, "@0R4")
  checkError(ret)
  ret = queryIsel(robot.sd, "@0R2")
  checkError(ret)
end

""" Initializes and references all axes in order Z,Y,X """
function initRefZYX(robot::IselRobot)
  initZYX(robot)
  refZYX(robot)
end

""" Move Isel Robot to center"""
function moveCenter(robot::IselRobot)
  moveAbs(robot, 0.0u"mm",0.0u"mm",0.0u"mm")
end

""" Move Isel Robot to park"""
function movePark(robot::IselRobot)
  moveAbs(robot, robot.defParkPos[1], 0.0u"mm", 0.0u"mm");
end

""" Move Isel Robot to teach position """
function moveTeachPos(robot::IselRobot)
    moveAbs(robot, 0.0u"mm" ,robot.defCenterPos[2],robot.defCenterPos[3])
    moveAbs(robot,robot.defCenterPos[1],robot.defCenterPos[2],robot.defCenterPos[3])
end

""" Move Isel Robot to teach sample center position """
function moveSampleCenterPos(robot::IselRobot)
    moveAbs(robot,robot.defSampleCenterPos[1],robot.defSampleCenterPos[2],robot.defSampleCenterPos[3])
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

function _getPosRaw(robot::IselRobot)
  ret = queryIsel(robot.sd, "@0P", 19)
  checkError(string(ret[1]))
  return ret[2:19]
end

function _getPos(robot::IselRobot)
  ret = _getPosRaw(robot)
  return parsePos(ret)
end

function parsePos(ret::AbstractString)
# 18 hex values, 6 digits per Axis order XYZ
  xPos=reinterpret(Int32, parse(UInt32,string("0x",ret[1:6])) << 8) >> 8
  yPos=reinterpret(Int32, parse(UInt32,string("0x",ret[7:12])) << 8) >> 8
  zPos=reinterpret(Int32, parse(UInt32,string("0x",ret[13:18])) << 8) >> 8
  #println(xPos,":",yPos,":",zPos)
  return xPos,yPos,zPos
end

""" Returns Pos in unit::Unitful.FreeUnits=u"mm" """
function getPos(robot::IselRobot,unit::Unitful.FreeUnits=u"mm")
  xPos,yPos,zPos = _getPos(robot)
  xyzPos = [steps2mm(xPos,robot.stepsPermm),steps2mm(yPos,robot.stepsPermm),steps2mm(zPos,robot.stepsPermm)]
  return map(x->uconvert(unit,x),xyzPos)
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

function _moveAbs(robot::IselRobot,stepsX,velX,stepsY,velY,stepsZ,velZ,isCheckError=true)
  # for z-axis two steps and velocities are needed compare documentation
  # set second z steps to zero
  cmd=string("@0M"," ",stepsX,",",velX,",",stepsY,",",velY,",",stepsZ,",",velZ,",",0,",",30)
  ret = queryIsel(robot.sd, cmd)
  if isCheckError
   return checkError(ret)
  else
   return ret
  end
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(robot::IselRobot,posX::typeof(1.0u"mm"), velX, posY::typeof(1.0u"mm"), velY, posZ::typeof(1.0u"mm"), velZ,isCheckError=true)
  _moveAbs(robot,mm2Steps(posX,robot.stepsPermm),velX,mm2Steps(posY,robot.stepsPermm),velY,mm2Steps(posZ,robot.stepsPermm),velZ,isCheckError)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0u"mm"), velX,
  distY::typeof(1.0u"mm"), velY,   distZ::typeof(1.0u"mm"), velZ)` """
function moveAbs(robot::IselRobot,posX::typeof(1.0u"mm"), posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"),isCheckError=true)
  moveAbs(robot,posX,robot.defaultVel[1],posY,robot.defaultVel[2],posZ,robot.defaultVel[3],isCheckError)
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

""" Gets the default IselRobot velocities of the axes x,y,z """
function getDefaultVelocity(robot::IselRobot)
    return robot.defaultVel
end

""" Sets the velocities of the axes x,y,z """
function setVelocity(robot::IselRobot, vel::Array{Int64,1})
    setVelocity(robot::IselRobot,vel[1],vel[2],vel[3])
end

""" Sets the velocities of the axes x,y,z """
function setVelocity(robot::IselRobot,xVel::Int64,yVel::Int64,zVel::Int64)
  minVel = robot.minMaxVel[1]
  maxVel = robot.minMaxVel[2]
  if minVel <= xVel && xVel <= maxVel && minVel <= yVel && yVel <= maxVel &&
      minVel <= zVel && zVel <= maxVel
  cmd = string("@0Id"," ",xVel,",",yVel,",",zVel,",",zVel)
  ret = queryIsel(robot.sd, cmd)
  checkError(ret)
  else
      error("Velocities set not in the range of [30,40000],
       you are trying to set xVel: ", xVel," yVel: ", yVel," zVel: ",zVel)
  end
end

""" Inverts the axes for y,z """
function invertAxesYZ(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0ID6")
    checkError(ret)
end

""" `prepareRobot(robot::IselRobot)` """
function prepareRobot(robot::IselRobot)
  # check sensor for reference
  tempTimeout = robot.sd.timeout_ms
  try
    robot.sd.timeout_ms = 180000
    refZYX(robot)
    moveTeachPos(robot)
    setZeroPoint(robot)
    movePark(robot)
  finally
    robot.sd.timeout_ms = tempTimeout
  end
end

""" Sets robots zero position at current position and saves new teach position in file .toml
 `TeachPosition(robot::IselRobot,fileName::AbstractString)` """
function TeachPosition(scanner::MPIScanner,robot::IselRobot,fileName::AbstractString)
    newTeachingPosition = getPos(robot,u"m")
    setZeroPoint(robot)
    # and most importantly change value defCenterPos in the .toml file to the new value
    # note the defCenterPos is saved in meter not in millimeter
    saveTeachPosition(newTeachingPosition,fileName)
    scanner.params["Robot"]["defCenterPos"] = ustrip(newTeachingPosition)
    println("Changed \"defCenterPos\" to $(newTeachingPosition) in $(fileName) file using the this Isel Robot")
end

""" Saves teach position to .toml file
`saveTeachPosition(position::Array{typeof(1.0u"m"),1},file::AbstractString)` """
function saveTeachPosition(position::Array{typeof(1.0u"m"),1},file::AbstractString)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)
    params["Robot"]["defCenterPos"] = ustrip(position)
    open(filename,"w") do f
        TOML.print(f,params)
    end
end

function checkError(ret::AbstractString)
  if ret != "0"
    error("Command failed: ",iselErrorCodes[ret])
  end
  return nothing
end

""" `readIOInput(robot::IselRobot)` returns an `Array{Bool,1}` of the 1-8 input slots"""
function readIOInput(robot::IselRobot)
    ret = queryIsel(robot.sd, "@0b0", 3)
    checkError(string(ret[1]))
    inputBin = bin(parse(UInt8,string("0x",ret[2:3])))
    inputArray = map(x->parse(Int64,x),collect(inputBin))
    return convert(Array{Bool,1},inputArray)
end

""" `readIOInput(robot::IselRobot,input::Int64)` returns an Bool for the `input` slot"""
function readIOInput(robot::IselRobot,input::Int64)
    if 1<= input && input <= 8
        return readIOInput(robot)[input]
    else
        error("input: $(input) needs to be between 1-8")
    end
end

function _writeIOOutput(robot::IselRobot,output::String)
    cmd = string("@0B0,", output)
    ret = queryIsel(robot.sd, cmd)
    checkError(ret)
end

""" `writeIOOutput(robot::IselRobot,output::Array{Bool,1})` output represents 1-8 output slots"""
function writeIOOutput(robot::IselRobot,output::Array{Bool,1})
    outputInt=convert(Array{Int64,1},output)
    outputStrings = map(x->string(x),outputInt)
    outputBin=parse(UInt8,string("0b",string(outputStrings...)))
    _writeIOOutput(robot,dec(outputBin))
end
