using MPIMeasurements

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[0.02]
params["acqNumAverages"]=1000
params["calibFieldToVolt"]=[20.509]#dfstrength*calibF2V=Uout1Rp
params["calibRefToField"]=[0.0133]#[0.013242]calibR2F*Uref=Field

measurementCont(daq, params, controlPhase=true)
