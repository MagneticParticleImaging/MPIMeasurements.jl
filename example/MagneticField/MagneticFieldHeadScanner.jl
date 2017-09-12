using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shp = [10,2,1]
fov = [200.0,200.0,1.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

# create Scanner
scanner = MPIScanner("IselRobot.toml")
robot = scanner.robot
scannerSetup = hallSensorRegularScanner

gaussmeter = GaussMeter("/dev/ttyUSB1")
mfMeasObj = MagneticFieldMeas(gaussmeter, u"mT",
               Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())


# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)
setAllRange(gaussmeter, '2')
MPIMeasurements.setFast(gaussmeter, '1')

@time res = performTour!(robot, scannerSetup, positions, mfMeasObj)

saveMagneticFieldAsHDF5(mfMeasObj, "/home/labuser/TestBackground.hd5", 0.25u"Tm^-1")
