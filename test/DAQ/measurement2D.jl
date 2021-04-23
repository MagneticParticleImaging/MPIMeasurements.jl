using MPIMeasurements
using PyPlot

function plotData(u, daq, fignum)
    figure(fignum)
    clf()
    subplot(4,1,1)
    plot(vec(u[:,1,:,:]),"r")
    subplot(4,1,2)
    semilogy(freq[idx]/1000, abs.(rfft(vec(u[:,1,:,:])))[idx],"ro-")
    xlabel("freq / kHz")
    subplot(4,1,3)
    plot(vec(u[:,2,:,:]),"b")
    subplot(4,1,4)
    semilogy(freq[idx]/1000, abs.(rfft(vec(u[:,2,:,:])))[idx],"bo-")
    xlabel("freq / kHz")
    savefig("images/control$(fignum).png")
end



include("config.jl")

scanner = MPIScanner("TestSingleRP2D.toml")
daq = getDAQ(scanner)

numFreq = div(daq.params.rxNumSamplingPoints,2)+1
freq = collect(0:(numFreq-1))./(numFreq-1).*daq.params.rxBandwidth
idx = 70:80

params = toDict(daq.params)

params["studyName"] = "Test"
params["studyDescription"] = "A very cool measurement"
params["scannerOperator"] = "Tester"
params["dfStrength"] = [0.05, 0.05]
params["dfPhase"] = [pi/2, pi/2]
params["dfWaveform"] = "SINE"
params["acqNumFrames"] = 1
params["acqNumAverages"] = 1
params["controlLoopAmplitudeAccuracy"] = 0.0001


params["correctCrossCoupling"] = false
params["controlPhase"] = false
uNoControl = measurement(daq, params)
plotData(uNoControl, daq, 1)


scanner = MPIScanner("TestSingleRP2D.toml")
daq = getDAQ(scanner)
params["correctCrossCoupling"] = false
params["controlPhase"] = true
uNoCorr = measurement(daq, params)
plotData(uNoCorr, daq, 2)

#=
scanner = MPIScanner("TestSingleRP2D.toml")
daq = getDAQ(scanner)
params["correctCrossCoupling"] = true
params["controlPhase"] = true
uCorr = measurement(daq, params)
plotData(uCorr, daq, 3)



figure(4)
clf()
subplot(2,1,1)
semilogy(freq[idx]/1000, abs.(rfft(vec(uCorr[:,1,:,:])))[idx],"ro-")
semilogy(freq[idx]/1000, abs.(rfft(vec(uNoCorr[:,1,:,:])))[idx],"rx--")
legend(["Coupling Corr", "No Coupling Corr"])
ylabel("DF Signal / a.u.")
xlabel("freq / kHz")
subplot(2,1,2)
semilogy(freq[idx]/1000, abs.(rfft(vec(uCorr[:,2,:,:])))[idx],"bo-")
semilogy(freq[idx]/1000, abs.(rfft(vec(uNoCorr[:,2,:,:])))[idx],"bx--")
legend(("Coupling Corr", "No Coupling Corr"))
ylabel("DF Signal / a.u.")
xlabel("freq / kHz")
subplots_adjust(left=0.15,right=0.95, bottom=0.1, top=0.95, hspace=0.4,wspace=0.4)
savefig("images/control4.png")
=#