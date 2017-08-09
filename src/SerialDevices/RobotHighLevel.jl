export acquireMeas!, acquireHeadSys
export MeasObj

# abstract supertype for all measObj etc.
@compat abstract type MeasObj end

function _acquireMeas!(scanner::BaseScanner, grid::AbstractGrid, measObj::T,
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

""" `acquireMeas(scanner::BaseScanner, grid::RegularGrid{typeof(1.0u"mm")}, measObj::T, preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj}`
Derive your own MeasObj from MeasObj for your purposes, and define your own pre/postMoveAction Function!
"""
acquireMeas!(scanner::BaseScanner, grid::RegularGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas!(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas!(scanner::BaseScanner, grid::MeanderingGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas!(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas!(scanner::BaseScanner, grid::ArbitraryGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas!(scanner,grid,measObj,preMoveAction,postMoveAction)
acquireMeas!(scanner::BaseScanner, grid::ChebyshevGrid{typeof(1.0u"mm")}, measObj::T,
  preMoveAction::Function, postMoveAction::Function) where {T<:MeasObj} = _acquireMeas!(scanner,grid,measObj,preMoveAction,postMoveAction)

@compat struct HeadSysMeas <: MeasObj
  # ioCard Todo
  positions::Array{Vector{typeof(1.0u"mm")},1}
  signals::Array{Vector{typeof(1.0u"mV")},1}
end

function acquireHeadSys(grid::AbstractGrid)
  hR = iselRobot("/dev/ttyS0")
  hS = Scanner{IselRobot}(:Scanner, hR, dSampleRegularScanner, ()->())

  headSysMeas = HeadSysMeas(Array{Vector{typeof(1.0u"mm")},1}(),Array{Vector{typeof(1.0u"mV")},1}())
  acquireMeas!(hS, grid, headSysMeas,  preMoveHeadSys, postMoveHeadSys)
  # save headSysMeas as MDF ...
  return headSysMeas
end

function preMoveHeadSys(measObj::HeadSysMeas, pos::Array{typeof(1.0u"mm"),1})
  # nothing todo
end

function postMoveHeadSys(measObj::HeadSysMeas, pos::Array{typeof(1.0u"mm"),1})
  println("post action: ", pos)
  push!(measObj.positions, pos)
  #get signal value form io card
  signalValues =[1.0u"mv",2.0u"mV",1.0u"mV"]
  push!(measObj.signals, signalValues)
end
