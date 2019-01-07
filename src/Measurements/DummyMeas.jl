export DummyMeasObj

struct DummyMeasObj <: MeasObj
end

# Initialize GaussMeter with standard settings
#setStandardSettings(mfMeasObj.gaussMeter)
function preMoveAction(measObj::DummyMeasObj, pos::Array{typeof(1.0Unitful.mm),1}, index)
  @info "moving to position" pos
end

# define postMoveAction
function postMoveAction(measObj::DummyMeasObj, pos::Array{typeof(1.0Unitful.mm),1}, index)
  @info "post action"
end
