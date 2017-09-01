export DummyRobot

struct DummyRobot <: AbstractRobot
end


function moveAbs(robot::DummyRobot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  println("DummyRobot: move to pos $posX  $posY  $posZ")
  sleep(1.0)
end

function movePark(robot::DummyRobot)
  println("Moving to Park Position!")
end
