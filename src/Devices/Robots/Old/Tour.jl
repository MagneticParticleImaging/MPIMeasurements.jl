export performTour!, postMoveAction, preMoveAction


""" `performTour(scanner::BaseScanner, grid::Positions, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
function performTour!(robot::Robot, setup::RobotSetup, positions::Positions,
          measObj::T, postMoveWaitTime=0.01, switchBrakes=false, vel=getDefaultVelocity(robot); coolingDown::Bool=false) where {T<:MeasObj}

  # check all coords for safety
  for pos in positions
    isValid = checkCoords(setup, pos, getMinMaxPosX(robot))
  end

  for (index,pos) in enumerate(positions)
    # Abkuehlpause
    if index == round(Int,length(positions)/2) && coolingDown
      println("Cooled down? Enter \"yes\"")
      while readline() != "yes"
        println("Cooled down? Enter \"yes\"")
      end
    end

    preMoveAction(measObj, pos, index)
    moveAbsUnsafe(robot, pos, vel) # comment for testing
    sleep(postMoveWaitTime)
    if switchBrakes
      setBrake(robot,false)
    end
    postMoveAction(measObj, pos, index)
    if switchBrakes
      setBrake(robot,true)
    end
  end

  movePark(robot)
  return measObj
end
