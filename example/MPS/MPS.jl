using MPIMeasurements

params = Dict{String,Any}()
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=[20e-3]

daq = DAQ("MPS.ini") #With custom server => continuous samples
#daq = DAQ("MPSScpi.ini") #With Scpi interface => higher sampling rate

# This version does not store the data
#u = measurement(daq, params, controlPhase=false)

# This version does store the data in a custom location
#filename = measurement(daq,"/home/knopp/test.mdf", params, background=true, controlPhase=false)

# This version does store the data in the MDFStore
filename = measurement(daq, MDFStore, params, background=false, controlPhase=true)

u = loadBGCorrData(filename)

showDAQData(daq,u)
