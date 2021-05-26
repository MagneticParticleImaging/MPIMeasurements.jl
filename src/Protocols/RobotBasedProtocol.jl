
abstract type RobotBasedProtocol <: Protocol end

positions(protocol::RobotBasedProtocol)::Positions = protocol.positions
postMoveWaitTime(protocol::RobotBasedProtocol)::typeof(1.0u"s") = protocol.postMoveWaitTime
numCooldowns(protocol::RobotBasedProtocol)::Integer = protocol.numCooldowns
robotVelocity(protocol::RobotBasedProtocol)::typeof(1.0u"m/s") = protocol.numCooldowns
switchBrakes(protocol::RobotBasedProtocol)::Bool = protocol.switchBrakes


function execute(protocol::RobotBasedProtocol)
  scanner_ = scanner(protocol)
  robot = getRobot(scanner_)

  positions_ = positions(protocol)
  vel = robotVelocity(protocol)
  switchBrakes_ = switchBrake(protocol)
  
  for (index, pos) in enumerate(positions_)
    # Cooldown pause
    numCooldowns_ = numCooldowns(protocol)
    if numCooldowns_ > 0 && index == round(Int, length(positions)/numCooldowns_)
      println("Cooled down? Enter \"yes\"")
      while readline() != "yes"
        println("Cooled down? Enter \"yes\"")
      end
    end

    preMoveAction(protocol)
    moveAbs(robot, pos, vel)
    sleep(postMoveWaitTime)

    if hasBrake(robot) && switchBrakes_
      setBrake(robot, false)
    end

    postMoveAction(protocol)

    if hasBrake(robot) && switchBrakes_
      setBrake(robot, true)
    end
  end

  movePark(robot)
end



@mustimplement preMoveAction(protocol::RobotBasedProtocol)
@mustimplement postMoveAction(protocol::RobotBasedProtocol)

