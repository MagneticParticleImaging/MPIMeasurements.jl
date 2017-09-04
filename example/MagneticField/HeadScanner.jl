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

robot = DummyRobot()
scannerSetup = hallSensorRegularScanner

struct MyMeasObj <: MeasObj
  rp::RedPitaya
end

rp = RedPitaya("192.168.1.20")
measObj = MyMeasObj(rp)

# Initialize GaussMeter with standard settings
#setStandardSettings(mfMeasObj.gaussMeter)

# define preMoveAction
function preMoveAction(measObj::MyMeasObj, pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")

end

# define postMoveAction
function postMoveAction(measObj::MyMeasObj, pos::Vector{typeof(1.0u"mm")}, index)
  println("post action: ", pos)

  newvoltage = rand()
  value(rp,"AOUT0",newvoltage)
  println( "Set DC source $newvoltage   $(value(measObj.rp,"AIN2")) " )

  #sleep(1.0)
  #getPosition(measObj, pos)
  #getXYZValues(measObj)
  #println(measObj.magneticField[end])
end

res = performTour!(robot, scannerSetup, positions, measObj)

#move back to park position after measurement has finished
movePark(robot)

#saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm.hd5", 2.5u"Tm^-1")
