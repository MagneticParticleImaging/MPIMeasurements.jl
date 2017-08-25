using MPIMeasurements

params = Dict{String,Any}()
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[20e-3]

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

# This version does not store the data
#u = measurement(daq, params, controlPhase=true)

# This version does store the data in a custom location
filename = measurement(daq,"/home/labuser/test.mdf", params, controlPhase=true)

# This version does store the data in the MDFStore
#filename = measurement(daq, MDFStore, params,  controlPhase=true)

#u = loadBGCorrData(filename)

showDAQData(daq,u)
