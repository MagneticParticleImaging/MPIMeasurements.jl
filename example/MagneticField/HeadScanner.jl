using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shape = [5,5,1]
fov = [200.0,200.0,1.0]u"mm"
center = [0.0,0.0,0.0]u"mm"
positions = MeanderingGridPositions( CartesianGridPositions(shape,fov,center) )

# create Scanner
#scanner = MPIScanner("HeadScanner.toml")
scanner = MPIScanner("DummyScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)
gauss = getGaussMeter(scanner)
rp = RedPitaya("192.168.1.20")
waitTime = 10.0
currRange = 1.0:3.0:10.0
currents = hcat(hcat(currRange,zeros(length(currRange)))',
                hcat(zeros(length(currRange)),currRange)',
                hcat(currRange,currRange)')

#TODO mT sollte man hier nicht angeben müssen. Das sollte im Gaussmeter gekapselt sein
mfMeasObj = MagneticFieldSweepCurrentsMeas(rp, gauss, u"mT", positions, currents, waitTime)

@time res = performTour!(robot, safety, positions, mfMeasObj)

filenameField = joinpath(homedir(),"TestBackground.h5")
saveMagneticFieldAsHDF5(mfMeasObj, filenameField)

pos, field = loadMagneticField(filenameField)

MPISimulations.plotMagneticField(field, pos, 3, 1)
