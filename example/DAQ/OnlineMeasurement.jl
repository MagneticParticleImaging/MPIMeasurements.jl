using MPIMeasurements

scanner = MPIScanner("HeadScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[5e-3]  #[5e-3]
params["acqNumAverages"]=100
#params["calibFieldToVolt"]=[1]
#x = linspace(0,1,6)
#params["acqFFValues"] = [0.0]
#params["acqNumFFChannels"] = 2
#params["acqFFValues"] = repeat( x, inner=10)
#params["acqNumPeriodsPerFrame"]= div(length(params["acqFFValues"]),params["acqNumFFChannels"])

enableSlowDAC(daq,true)
println("Starting Measurement...")
measurementCont(daq, params, controlPhase=true, showFT=true)
