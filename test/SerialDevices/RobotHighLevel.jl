using MPIMeasurements
using Base.Test
using Unitful
using Compat


# define Grid
rG = RegularGrid{typeof(1.0u"mm")}([2,2,2],[3.0,3.0,3.0]u"mm",[0.0,0.0,0.0]u"mm")

# create Scanner
bR = brukerRobot("RobotServer")
bS = BrukerScanner{BrukerRobot}(:BrukerScanner, bR, dSampleRegularScanner, ()->())

# define measObj
@compat struct MagneticFieldMeas <: MeasObj
  #serialDevice::SerialDevice{GaussMeter}
  positions::Array{Vector{typeof(1.0u"mm")},1}
  magneticField::Array{Vector{typeof(1.0u"mT")},1}
end
mfMeasObj = MagneticFieldMeas(Array{Vector{typeof(1.0u"mm")},1}(),Array{Vector{typeof(1.0u"mT")},1}())

# define preMoveAction
function preMA(measObj::MagneticFieldMeas, pos::Array{typeof(1.0u"mm"),1})
  println("pre action: ", pos)

end

# define postMoveAction
function postMA(measObj::MagneticFieldMeas, pos::Array{typeof(1.0u"mm"),1})
  println("post action: ", pos)
  push!(measObj.positions, pos)
  #magValues=[getXValue(measObj.serialDevice), getYValue(measObj.serialDevice), getZValue(measObj.serialDevice)]*u"mT"
  magValues =[1.0u"mT",2.0u"mT",1.0u"mT"]
  push!(measObj.magneticField, magValues)
end

res = acquireMeas(bS, rG, mfMeasObj, preMA, postMA)

positionsArray=hcat(res.positions...)
magArray=hcat(res.magneticField...)
