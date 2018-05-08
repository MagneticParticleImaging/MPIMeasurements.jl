using MPIMeasurements
using HDF5

scanner = MPIScanner("HeadScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[5e-3]  #[5e-3]
params["acqNumAverages"]=1000
#params["calibFieldToVolt"]=[1]

params["acqFFSequence"] = "HeadScanner102Triangle"
#params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

robot = getRobot(scanner)
S,S2 = measurementContReadAndSave(daq, robot, params, controlPhase=true, showFT=true)

h5write("systemMatrixNew.h5","/matrix",S)
h5write("phantom.h5","/matrix",S2)
