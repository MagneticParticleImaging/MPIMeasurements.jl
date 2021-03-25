using MPIMeasurements

scanner = MPIScanner("DummyScanner.toml")
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"]="TestDummy"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Dummy"
params["dfStrength"]=[1e-3]
params["acqNumFrames"]=100
params["acqNumAverages"]=10

# Can't have a measurement under Windows yet due to not including Measurements.jl in main file
#filename = measurement(daq, params, MDFStore, controlPhase=true)
