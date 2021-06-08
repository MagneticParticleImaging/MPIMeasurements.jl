using MPIMeasurements
using PyPlot

params = Dict{String,Any}()
params["studyName"]="TemporalValidation"
params["studyDescription"]="HarmonicValidation over time"
params["scannerOperator"]="FloThieben"
params["dfStrength"]=[20e-3]

scanner = MPIScanner("MPS.toml")
daq = getDAQ(scanner)

delay = 10.0
numRepetitions = 100

# This version does not store the data
#u = measurement(daq, params, controlPhase=true)

# This version does store the data in a custom location
#filename = measurementRepeatability(daq,"/home/labuser/TemporalValidation.mdf", numRepetitions,
#                                     delay, params, controlPhase=true)
filename = "/home/labuser/TemporalValidation.mdf"

# This version does store the data in the MDFStore
#filename = measurementRepeatability(daq, MDFStore, params,  controlPhase=true)
f = MPIFile(filename)

u = getMeasurements(f, false, #frames=measFGFrameIdx(f),
            fourierTransform=true, bgCorrection=true,
             tfCorrection=false)

#showDAQData(daq,u)
