using MPIMeasurements
using PyPlot

include("config.jl")

scanner = MPIScanner(conf)
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"] = "Test"
params["studyDescription"] = "A very cool measurement"
params["scannerOperator"] = "Tester"
params["dfStrength"] = [1e-3]
params["dfWaveform"] = "SINE"
params["acqNumFrames"] = 10
params["acqNumAverages"] = 10

u, uSlowADC = measurement(daq, params, controlPhase=true)
#filename = measurement(daq, params, MDFStore, controlPhase=true)

figure(1)
clf()
plot(vec(u))
savefig("images/im1.png")

scanner = MPIScanner(conf) #what???
daq = getDAQ(scanner)
params["dfWaveform"] = "TRIANGLE"
u, uSlowADC = measurement(daq, params, controlPhase=false)
figure(1)
clf()
plot(vec(u))
savefig("images/im2.png")