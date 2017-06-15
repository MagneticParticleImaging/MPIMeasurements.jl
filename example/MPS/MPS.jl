using MPIMeasurements

params = Dict{String,Any}()
params["studyName"]="TestTobi"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Tobi"
params["dfStrength"]=20e-3

mps = MPS()
#mps = MPS("192.168.1.20")

# This version does not store the data
#u = measurement(mps, params)

# This version does store the data in a custom location
#filename = measurement(mps,"/home/knopp/test.mdf", params)

# This version does store the data in the MDFStore
filename = measurement(mps, MDFStore, params)

u = loadMPSData(filename)

showMPSData(mps,u)
