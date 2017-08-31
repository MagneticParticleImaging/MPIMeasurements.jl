export performTour!
export MeasObj

# abstract supertype for all measObj etc.
@compat abstract type MeasObj end

""" `performTour(scanner::BaseScanner, grid::Positions, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
function performTour!(scanner::BaseScanner, grid::Positions, measObj::T,
  preMoveAction::Function, postMoveAction::Function, postMoveWaitTime=0.01) where {T<:MeasObj}

  rSetup = robotSetup(scanner)
  # check all coords for safety
  for pos in grid
     isValid = checkCoords(rSetup, pos)
  end

  for pos in grid
    preMoveAction(measObj, pos)
    moveAbs(scanner, pos) # comment for testing
    sleep(postMoveWaitTime)
    postMoveAction(measObj, pos)
  end
  return measObj
end
