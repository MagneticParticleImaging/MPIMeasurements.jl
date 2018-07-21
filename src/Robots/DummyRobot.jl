export DummyRobot

mutable struct DummyRobot <: Robot
  referenced::Bool

  DummyRobot() = new(false)
end

function moveAbs(robot::DummyRobot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  println("DummyRobot: move to pos $posX  $posY  $posZ")
  sleep(0.05)
end

function moveRel(robot::DummyRobot, distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
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

function prepareRobot(robot::DummyRobot)
  println("Doing Dummy Reference Drive!")
  robot.referenced = true
end

isReferenced(robot::DummyRobot) = robot.referenced
getDefaultVelocity(robot::DummyRobot) = zeros(3)+20000
parkPos(robot::DummyRobot) = [0.0u"mm",0.0u"mm",0.0u"mm"]

function setVelocity(robot::DummyRobot, vel::Array{Int64,1})
    println("Setting velcities for Dummy Robot!")
end
