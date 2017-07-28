export acquireMeas
export MeasObj

# abstract supertype for all measObj etc.
@compat abstract type MeasObj end

function _acquireMeas(scanner::Scanner, grid::AbstractGrid, measObj::T,
  preMoveAction::Function, postMoveAction::Function, postMoveWaitTime=0.01) where {T<:MeasObj}

  rSetup = robotSetup(scanner)
  # check all coords for safety
  for pos in grid
     isValid = checkCoords(rSetup, pos)
  end

  for pos in grid
    preMoveAction(measObj, pos)
    moveAbs(scanner, pos)
    sleep(postMoveWaitTime)
    postMoveAction(measObj, pos)
  end
  return measObj
end

""" `acquireMeas(scanner::Scanner, grid::RegularGrid{typeof(1.0u"mm")}, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
acquireMeas(scanner::Scanner, grid::RegularGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas(scanner::Scanner, grid::MeanderingGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas(scanner::Scanner, grid::ArbitraryGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas(scanner::Scanner, grid::ChebyshevGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas(scanner,grid,measObj,preMoveAction,postMoveAction)
