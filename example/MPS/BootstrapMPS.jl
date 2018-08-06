using MPIMeasurements

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[0.02]
params["acqNumAverages"]=1000
#iterativ setting of calibFieldToVolt
#start with dfstrength=1 and calibFieldToVolt=0.98 
params["calibFieldToVolt"]=[12.91]
params["calibRefToField"]=[0.012195]

measurementCont(daq, params, controlPhase=true)
