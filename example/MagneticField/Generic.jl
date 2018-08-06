using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shape = [5,5,1]
fov = [200.0,200.0,1.0]Unitful.mm
center = [0.0,0.0,0.0]Unitful.mm
positions = MeanderingGridPositions( RegularGridPositions(shape,fov,center) )

# create Scanner
#scanner = MPIScanner("HeadScanner.toml")
scanner = MPIScanner("DummyScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)
gaussmeter = getGaussMeter(scanner)

#TODO mT sollte man hier nicht angeben müssen. Das sollte im Gaussmeter gekapselt sein
mfMeasObj = MagneticFieldMeas(gaussmeter, Unitful.mT, positions)

@time res = performTour!(robot, safety, positions, mfMeasObj)

filenameField = joinpath(homedir(),"TestBackground.h5")
saveMagneticFieldAsHDF5(mfMeasObj, filenameField)

pos, field = loadMagneticField(filenameField)

MPISimulations.plotMagneticField(field, pos, 3, 1)
