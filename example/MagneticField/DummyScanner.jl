using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5
import MPIMeasurements: preMoveAction, postMoveAction

# define Grid
shp = [3,3,1]
fov = [10.0,10.0,1.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

scanner = MPIScanner("DummyScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)

res = performTour!(robot, safety, positions, DummyMeasObj())

#move back to park position after measurement has finished
movePark(robot)
