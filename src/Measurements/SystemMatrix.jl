export acquireHeadSys

@compat struct HeadSysMeas <: MeasObj
  # ioCard Todo
  positions::Array{Vector{typeof(1.0u"mm")},1}
  signals::Array{Vector{typeof(1.0u"mV")},1}
end

function acquireHeadSys(grid::Positions)
  hR = iselRobot("/dev/ttyS0")
  hS = Scanner{IselRobot}(:Scanner, hR, dSampleRegularScanner, ()->())

  headSysMeas = HeadSysMeas(Array{Vector{typeof(1.0u"mm")},1}(),Array{Vector{typeof(1.0u"mV")},1}())
  performTour!(hS, grid, headSysMeas,  preMoveHeadSys, postMoveHeadSys)
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
