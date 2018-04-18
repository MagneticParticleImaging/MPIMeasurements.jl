using MPIMeasurements

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[1]
params["acqNumAverages"]=1000
params["calibFieldToVolt"]=[0.98]

#
measurementCont(daq, params, controlPhase=false)
