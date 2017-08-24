include("GaussMeterFunctions.jl")


# define Grid
rG = loadTDesign(3,8,30u"mm")

# create Scanner
bR = brukerRobot("RobotServer")
bS = Scanner{BrukerRobot}(:BrukerScanner, bR, hallSensorRegularScanner, ()->())

mfMeasObj = MagneticFieldMeas(gaussMeter("/dev/ttyUSB0"),u"T",Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())


# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)
#setRange(mfMeasObj)

# define preMoveAction
function preMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("pre action: ", pos)

end

# define postMoveAction
function postMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("post action: ", pos)
  sleep(1.0)
  getPosition(measObj, pos)
  getXYZValues(measObj)

end

res = acquireMeas!(bS, rG, mfMeasObj, preMA, postMA)

#move back to park position after measurement has finished
movePark(bS)

saveMagneticFieldAsHDF5(mfMeasObj, filename, grad::Float64)

#positionsArray=hcat(res.positions...)
#magArray=hcat(res.magneticField...)
