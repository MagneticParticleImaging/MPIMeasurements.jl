using MPIMeasurements

scanner = MPIScanner("HeadScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[5e-3]  #[5e-3]
params["acqNumAverages"]=1000
#params["calibFieldToVolt"]=[1]
x = linspace(0,1,3)
params["acqFFValues"] = [0.0]
#params["acqFFValues"] = repeat( cat(1,x,reverse(x[2:end-1])),inner=5)
params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])


measurementCont(daq, params, controlPhase=true, showFT=true)
