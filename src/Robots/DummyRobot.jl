export DummyRobot

struct DummyRobot <: AbstractRobot
end

function moveAbs(robot::DummyRobot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  println("DummyRobot: move to pos $posX  $posY  $posZ")
  sleep(1.0)
end

function moveRel(robot::DummyRobot, distX::typeof(1.0u"mm"),
  distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
  println("DummyRobot: move distance $distX  $distY  $distZ")
  sleep(1.0)
end

function movePark(robot::DummyRobot)
  println("Moving to Park Position!")
end

function moveCenter(robot::DummyRobot)
  println("Moving to Center Position!")
end