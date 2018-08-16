export DummyRobot

mutable struct DummyRobot <: Robot
  referenced::Bool

  DummyRobot() = new(true)
end

function moveAbs(robot::DummyRobot, posX::typeof(1.0Unitful.mm),
  posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm))
  println("DummyRobot: move to pos $posX  $posY  $posZ")
  sleep(0.05)
end

""" Moves absolute in mm `moveRel(sd::SerialDevice{IselRobot},distX::typeof(1.0Unitful.mm), velX,
  distY::typeof(1.0Unitful.mm), velY,   distZ::typeof(1.0Unitful.mm), velZ)` """
function moveAbs(robot::DummyRobot,posX::typeof(1.0Unitful.mm), velX, posY::typeof(1.0Unitful.mm), velY, posZ::typeof(1.0Unitful.mm), velZ,isCheckError=true)
    println("DummyRobot: move to pos $posX $velX  $posY $velY $posZ $velZ")
    sleep(0.05)
end

function moveRel(robot::DummyRobot, distX::typeof(1.0Unitful.mm),
  distY::typeof(1.0Unitful.mm), distZ::typeof(1.0Unitful.mm))
  println("DummyRobot: move distance $distX  $distY  $distZ")
  sleep(0.05)
end

function movePark(robot::DummyRobot)
  println("Moving to Park Position!")
end

function moveCenter(robot::DummyRobot)
  println("Moving to Center Position!")
end

function setBrake(robot::DummyRobot, brake::Bool)
    println("Setting brake to $(brake) !")
end

function setEnabled(robot::DummyRobot, enabled::Bool)
    println("Setting enabled $(enabled) !")
end

function prepareRobot(robot::DummyRobot)
  println("Doing Dummy Reference Drive!")
  robot.referenced = true
end

isReferenced(robot::DummyRobot) = robot.referenced
getDefaultVelocity(robot::DummyRobot) = zeros(Int64,3)+20000
parkPos(robot::DummyRobot) = [0.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm]

function setRefVelocity(robot::DummyRobot, vel::Array{Int64,1})
    println("Setting velcities for Dummy Robot!")
end

function getMinMaxPosX(robot::DummyRobot)
    return [-70.0Unitful.mm, 200.0Unitful.mm]
end
