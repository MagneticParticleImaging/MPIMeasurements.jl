using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shape = [10,10,1]
fov = [200.0,200.0,1.0]u"mm"
center = [0.0,0.0,0.0]u"mm"
positions = MeanderingGridPositions( RegularGridPositions(shape,fov,center) )

# create Scanner
scanner = MPIScanner("HeadScanner.toml")
#scanner = MPIScanner("DummyScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)
gauss = getGaussMeter(scanner)
rp = RedPitaya("192.168.1.100")
waitTime = 4.0
currRange = 2.0:2.0:10.0
currents = hcat(hcat(currRange,zeros(length(currRange)))',
                hcat(zeros(length(currRange)),currRange)',
                hcat(currRange,currRange)')
voltToCurrent = 0.08547008547008547

#TODO mT sollte man hier nicht angeben müssen. Das sollte im Gaussmeter gekapselt sein
mfMeasObj = MagneticFieldSweepCurrentsMeas(rp, gauss, u"mT", positions,
                                           currents, waitTime, voltToCurrent)

@time res = performTour!(robot, safety, positions, mfMeasObj)

filenameField = joinpath(homedir(),"MagneticField$(string(now())).h5")
saveMagneticFieldAsHDF5(mfMeasObj, filenameField)

pos, field = loadMagneticField(filenameField)

MPISimulations.plotMagneticField(field, pos, 3, 1)
