export performTour!


""" `performTour(scanner::BaseScanner, grid::Positions, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
function performTour!(robot::AbstractRobot, setup::RobotSetup, positions::Positions,
          measObj::T, postMoveWaitTime=0.01) where {T<:MeasObj}

  # check all coords for safety
  for pos in positions
     isValid = checkCoords(setup, pos)
  end

  for (index,pos) in enumerate(positions)
    preMoveAction(measObj, pos, index)
    moveAbsUnsafe(robot, pos) # comment for testing
    sleep(postMoveWaitTime)
    postMoveAction(measObj, pos, index)
  end
  return measObj
end
