using MPIMeasurements

filename = "systemMatrix.mdf"

# define Grid
shp = [5,3,1]
fov = [90.0,30.0,1.0]u"mm"
ctr = [156.0,-11.2,71.0]u"mm"

positions = BreakpointGridPositions(
        MeanderingGridPositions( RegularGridPositions(shp,fov,ctr) ),
        [1,11], [0.0,0.0,0.0]u"mm" )

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
params["acqNumAverages"]=1000
params["calibDeltaSampleSize"] = [10.0,10.0,10.0]u"mm"

x = linspace(0,1,3)
params["acqFFValues"] = []
#params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"] = 1 #length(params["acqFFValues"])

currents = [10.0, 10.0]

data = measurementSystemMatrix(su, daq, robot, safety, positions, filename,
                    currents, params, controlPhase=false, waitTime = 1.0, voltToCurrent = 0.08547008547008547)
