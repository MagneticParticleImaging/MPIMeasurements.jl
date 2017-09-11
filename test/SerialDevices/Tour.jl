using MPIMeasurements
using Base.Test
using Unitful
using Compat

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

# create Robot
dR = DummyRobot()

res = performTour!(dR, hallSensorRegularScanner, positions, DummyMeasObj())
#move back to park position after measurement has finished
movePark(robot)
