using MPIMeasurements

scanner = MPIScanner("HeadScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[10e-3]
params["decimation"]=32
params["acqNumFrames"]=5000
#params["acqNumAverages"]=1

x = linspace(0,1,5)
#params["acqFFValues"] = [0.0]
params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])


#measurementCont(daq, params, controlPhase=true, showFT=false)
u = measurement(daq, params, controlPhase=false)
