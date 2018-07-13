export performTour!, postMoveAction, preMoveAction


""" `performTour(scanner::BaseScanner, grid::Positions, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
function performTour!(robot::Robot, setup::RobotSetup, positions::Positions,
          measObj::T, postMoveWaitTime=0.01, switchBrakes=false, vel=getDefaultVelocity(robot)) where {T<:MeasObj}

  # check all coords for safety
  for pos in positions
    isValid = checkCoords(setup, pos)
  end

  setVelocity(robot, vel)

  for (index,pos) in enumerate(positions)
    preMoveAction(measObj, pos, index)
    moveAbsUnsafe(robot, pos) # comment for testing
    sleep(postMoveWaitTime)
    if switchBrakes
      setBrake(robot,false)
    end
    postMoveAction(measObj, pos, index)
    if switchBrakes
      setBrake(robot,true)
    end
  end

  setVelocity(robot, getDefaultVelocity(robot))

  moveCenter(robot)
  return measObj
end
