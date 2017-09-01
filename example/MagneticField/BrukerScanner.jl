using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Positions
positions = loadTDesign(8,36,30u"mm")

# create Scanner
robot = brukerRobot("RobotServer")
scannerSetup = hallSensorRegularScanner

mfMeasObj = MagneticFieldMeas(GaussMeter("/dev/ttyUSB2"),u"T",
               Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())


# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)

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

res = performTour!(robot, scannerSetup, positions, mfMeasObj, preMA, postMA)

#move back to park position after measurement has finished
movePark(robot)

saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm.hd5", 2.5u"Tm^-1")


#=
# measure at random positions within cube
# define Grid
seed = UInt32(42)
fov = [40,40,40.0]u"mm"
ctr = [0,0,0]u"mm"
N = UInt(20)
rG = UniformRandomPositions(N,seed,fov,ctr)

mfMeasObj = MagneticFieldMeas(gaussMeter("/dev/ttyUSB2"),u"T",Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())

res = acquireMeas!(bS, rG, mfMeasObj, preMA, postMA)

#move back to park position after measurement has finished
movePark(bS)

saveMagneticFieldAsHDF5(mfMeasObj, "/home/nmrsu/measurmenttmp/2_5Tm_rand.hd5", 2.5u"Tm^-1")
=#
