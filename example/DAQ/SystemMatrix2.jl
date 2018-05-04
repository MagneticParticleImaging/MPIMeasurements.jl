using MPIMeasurements
using HDF5

filename = "systemMatrix.h5"

# define Grid
shp = [9,1,1]
fov = [90.0,1.0,1.0]u"mm"
ctr = [156.0,-11.2,71.0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

scanner = MPIScanner("HeadScanner.toml")
robot = getRobot(scanner)
daq = getDAQ(scanner)
safety = getSafety(scanner)
su = getSurveillanceUnit(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[5e-3]
params["acqNumAverages"]=10000

x = linspace(0,1,3)
params["acqFFValues"] = Float64[]
#params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=1 #length(params["acqFFValues"])

currents = [10.0, 10.0]

data = measurementSystemMatrix(su, daq, robot, safety, positions,
                    currents, params,
                    controlPhase=true, waitTime = 0.5, voltToCurrent = 0.08547008547008547)


h5write(filename, "/matrix", data.signals)
