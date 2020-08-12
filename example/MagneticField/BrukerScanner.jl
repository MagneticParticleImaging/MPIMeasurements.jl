using MPIMeasurements

# define Positions
positions = loadTDesign(8,36,42Unitful.mm,[16.0,0.0,0.0]Unitful.mm)

# create Scanner
scanner = MPIScanner("BrukerScanner.toml")
#scanner = MPIScanner("DummyScanner.toml")
robot = getRobot(scanner)
safety = getSafety(scanner)
gauss = getGaussMeter(scanner)
gausMeterRange = 1

mfMeasObj = MagneticFieldMeas(gauss, positions, gausMeterRange)

# perform measurement
res = performTour!(robot, safety, positions, mfMeasObj)

movePark(robot)

#filenameField = joinpath(homedir(),"measurementtmp","MagneticField_G2.4_FF0mm0mm0mm.h5")
#saveMagneticFieldAsHDF5(mfMeasObj, filenameField)

filenameField = joinpath(homedir(),"measurementtmp","MagneticField_G0.6_FF10mm10mm10mm.h5")
saveMagneticFieldAsHDF5(mfMeasObj, filenameField)
