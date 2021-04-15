using MPIMeasurements
using PyPlot

#include("config.jl")

#scanner = MPIScanner(conf)
daq = getDAQ(scanner)

params = toDict(daq.params)

params["studyName"] = "Test"
params["studyDescription"] = "A very cool measurement"
params["scannerOperator"] = "Tester"
params["dfStrength"] = [1e-3]
params["dfPhase"] = [pi/2]
params["dfWaveform"] = "SINE"
params["acqNumFrames"] = 1
params["acqNumAverages"] = 1
params["controlPhase"] = false #true TODO
params["acqFFSequence"] = "None"

u = measurement(daq, params)

@info size(u)

figure(1)
clf()
plot(vec(u[:,1,1,1]))
savefig(joinpath(imgdir, "im1.png"))

scanner = MPIScanner(conf) #what???
daq = getDAQ(scanner)
params["dfWaveform"] = "TRIANGLE"
params["controlPhase"] = false
u = measurement(daq, params)
figure(1)
clf()
plot(vec(u[:,1,1,1]))
savefig(joinpath(imgdir, "im2.png"))