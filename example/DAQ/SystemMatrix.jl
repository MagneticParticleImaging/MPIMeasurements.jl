using MPIMeasurements

# define Grid
shp = [3,3,3]
fov = [3.0,3.0,3.0]u"mm"
ctr = [0,0,0]u"mm"
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
params["acqNumAverages"]=1000

x = linspace(0,1,3)
params["acqFFValues"] = [0.0]
#params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

currents = [10.0, 10.0]

data = measurementSystemMatrix(su, daq, robot, safety, positions,
                    currents, params,
                    controlPhase=true, waitTime = 4.0, voltToCurrent = 0.08547008547008547)
