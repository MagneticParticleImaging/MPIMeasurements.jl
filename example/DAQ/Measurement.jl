using MPIMeasurements

scanner = MPIScanner("HeadScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[1e-3]
params["acqNumFrames"]=100
params["acqNumAverages"]=10

x = linspace(0,1,5)
#params["acqFFValues"] = [0.0]
params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

#u = measurement(daq, params, controlPhase=false)
filename = measurement(daq, params, MDFStore, controlPhase=true)
