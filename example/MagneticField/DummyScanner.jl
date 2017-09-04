using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5
import MPIMeasurements: preMoveAction, postMoveAction

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

scanner = MPIScanner("HeadScanner.toml")

robot = getRobot(scanner) #DummyRobot()
scannerSetup = hallSensorRegularScanner

struct DummyMeasObj <: MeasObj
end

# Initialize GaussMeter with standard settings
#setStandardSettings(mfMeasObj.gaussMeter)

function preMoveAction(measObj::DummyMeasObj, pos::Vector{typeof(1.0u"mm"), index)
  println("moving to next position...")

end

# define postMoveAction
function postMoveAction(measObj::DummyMeasObj, pos::Vector{typeof(1.0u"mm")}, index)
  println("post action: ", pos)
  #sleep(1.0)
  #getPosition(measObj, pos)
  #getXYZValues(measObj)
  #println(measObj.magneticField[end])
end

res = performTour!(robot, scannerSetup, positions, DummyMeasObj())

#move back to park position after measurement has finished
movePark(robot)

#saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm.hd5", 2.5u"Tm^-1")
