export DummyMeasObj

struct DummyMeasObj <: MeasObj
end

# Initialize GaussMeter with standard settings
#setStandardSettings(mfMeasObj.gaussMeter)
function preMoveAction(measObj::DummyMeasObj, pos::Array{typeof(1.0Unitful.mm),1}, index)
  println("moving to next position...")
end

# define postMoveAction
function postMoveAction(measObj::DummyMeasObj, pos::Array{typeof(1.0Unitful.mm),1}, index)
  println("post action: ", pos)
end
