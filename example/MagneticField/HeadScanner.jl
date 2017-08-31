using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
caG = CartesianGridPositions(shp,fov,ctr)

# create Scanner
bR = iselRobot("/dev/ttyUSB1")
bS = Scanner{BrukerRobot}(:BrukerScanner, bR, hallSensorRegularScanner, ()->())

mfMeasObj = MagneticFieldMeas(gaussMeter("/dev/ttyUSB2"),u"T",Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())


# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)
#setRange(mfMeasObj)

# define preMoveAction
function preMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("moving to next position...")

end

# define postMoveAction
function postMA(measObj::MagneticFieldMeas, pos::Vector{typeof(1.0u"mm")})
  println("post action: ", pos)
  sleep(1.0)
  getPosition(measObj, pos)
  getXYZValues(measObj)
  println(measObj.magneticField[end])
end

res = performTour!(bS, rG, mfMeasObj, preMA, postMA)

#move back to park position after measurement has finished
movePark(bS)

saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm.hd5", 2.5u"Tm^-1")
