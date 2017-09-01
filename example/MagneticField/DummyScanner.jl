using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

robot = DummyRobot()
scannerSetup = hallSensorRegularScanner

struct DummyMeasObj <: MeasObj
end

# Initialize GaussMeter with standard settings
#setStandardSettings(mfMeasObj.gaussMeter)

# define preMoveAction
function preMA(measObj::DummyMeasObj, pos::Vector{typeof(1.0u"mm")})
  println("moving to next position...")

end

# define postMoveAction
function postMA(measObj::DummyMeasObj, pos::Vector{typeof(1.0u"mm")})
  println("post action: ", pos)
  #sleep(1.0)
  #getPosition(measObj, pos)
  #getXYZValues(measObj)
  #println(measObj.magneticField[end])
end

res = performTour!(robot, scannerSetup, positions, DummyMeasObj(), preMA, postMA)

#move back to park position after measurement has finished
movePark(robot)

#saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm.hd5", 2.5u"Tm^-1")
