using MPIFiles
using FFTW
using PyPlot

#close("all")

tfpath = "C:\\Users\\schumacherj\\.mpilab\\configs\\Kolibri\\TransferFunctions\\TF_Kolibri.h5"

# basepath = "C:\\Users\\schumacherj\\.mpilab\\data\\measurements\\20211117_114620_Filter probably working"
# basepath = "C:\\Users\\schumacherj\\.mpilab\\data\\measurements\\20211119_134753_PSF"
# basepath = "C:\\Users\\schumacherj\\Desktop\\Messungen\\20211117_114620_Filter probably working"
basepath = "C:\\Users\\schumacherj\\Desktop\\Messungen\\20211119_134753_PSF"

dataset = 5
file = MPIFile(joinpath(basepath, "$dataset.mdf"))
@info dataset experimentName(file)

dataFG = convert(Array{Float64, 3}, file.mmap_measData[:, 1, :, measFGFrameIdx(file)])
dataBG = convert(Array{Float64, 3}, file.mmap_measData[:, 1, :, measBGFrameIdx(file)])

dataFG = reshape(dataFG, (size(dataFG, 1), size(dataFG, 2)*size(dataFG, 3)))
dataBG = reshape(dataBG, (size(dataBG, 1), size(dataBG, 2)*size(dataBG, 3)))

# Clean all corrupted periods
minThreshold = -0.22
maxThreshold = 0.013

dataFGPeriodMaxima = vec(maximum(dataFG, dims=1))
dataBGPeriodMaxima = vec(maximum(dataBG, dims=1))

dataFGPeriodMinima = vec(minimum(dataFG, dims=1))
dataBGPeriodMinima = vec(minimum(dataBG, dims=1))

dataFGPeriodThreshIdx = findall((dataFGPeriodMaxima .< maxThreshold) .& (minThreshold .< dataFGPeriodMinima))
dataBGPeriodThreshIdx = findall((dataBGPeriodMaxima .< maxThreshold) .& (minThreshold .< dataBGPeriodMinima))

bgAveragedPeriod = mean(dataBG[:, dataBGPeriodThreshIdx], dims=2)

# figure(1)
# plot(bgAveragedPeriod)

tf = TransferFunction(tfpath)

# Substract averaged bg from every period in the signal and apply tf
tfPeriod = tf[1:313, 1]
dataProcessed = deepcopy(dataFG[:, dataFGPeriodThreshIdx])
for i=1:size(dataProcessed, 2)
  dataProcessed[:, i] -= bgAveragedPeriod
  # dataFGTD = rfft(dataFG[:, i])
  # dataFGTD ./= tfPeriod
  # dataFG[:, i] = irfft(dataFGTD, 625)
end

#signal = vec(mean(dataProcessed, dims=2))
signal = reshape(dataProcessed, prod(size(dataProcessed)))

# Calculate iron mass
c = 25 # mg/ml (Perimag plain)
d_capillary = 0.45e-3 # m
A = π*(d_capillary/2)^2
l = 2*6e-3/5
V = A*l
m = V*c*1e3

# figure(1)
# plot(diff(signal))
# title("Time Signal 9.5 µg Fe")
# xlabel("time/samples")
# ylabel("dM/dt")

# figure(2)
# plot(signal)
# title("Time Signal 9.5 µg Fe")
# xlabel("time/samples")
# ylabel("M")

figure(3)
signalFD = rfft(signal)
fs = rxBandwidth(file)*2
f = range(0, stop=fs/2, length=length(signalFD))
signalFD ./= tf[f, 1]
signalFD = abs.(signalFD)
semilogy(f, signalFD)
title("Spectrum 9.5 µg Fe")
xlabel("f")
ylabel("M")

#dataProcessed = reshape(dataProcessed, prod(size(dataProcessed)))

# tf = rxTransferFunction(file)
# inductionFactor = rxInductionFactor(file)

# J = size(dataProcessed,1)
# dataF = rfft(dataProcessed, 1)
# dataF[2:end,:,:,:] ./= tf[2:end,:,:,:]
# @warn "This measurement has been corrected with a Transfer Function. Name of TF: $(rxTransferFunctionFileName(f))"
# if inductionFactor != nothing
#   dataF[:,k,:,:] ./= inductionFactor[1]
# end
# dataProcessed = irfft(dataF,J,1)

#figure(dataset)
#plot(reshape(dataFG[:, dataFGPeriodThreshIdx], prod(size(dataFG[:, dataFGPeriodThreshIdx]))), label="Foreground")
#plot(reshape(dataBG[:, dataBGPeriodThreshIdx], prod(size(dataBG[:, dataBGPeriodThreshIdx]))), label="Background")
#plot(dataProcessed, label="BG and TF corrected")
#legend()

# dataFD = abs.(rfft(dataFG-dataBG))
# dataBGFD = abs.(rfft(dataBG))
# dataProcessedFD = abs.(rfft(dataProcessed))
# fs = rxBandwidth(file)*2
# f = range(0, stop=fs/2, length=length(dataProcessedFD))
# figure(dataset*2)
# semilogy(f, dataFD, label="Signal-Leer")
# semilogy(f, dataBGFD, label="Leer")
# semilogy(f, dataProcessedFD, label="BG and TF corrected")
# legend()

#tf = TransferFunction("C:\\Users\\schumacherj\\.mpilab\\configs\\Kolibri\\TransferFunctions\\TF_Kolibri.h5")
#plot(tf.freq, abs.(tf.data.*(-1im*2*pi*tf.freq))/6e10)
#plot(tf.freq, angle.(tf.data.*(-1im*2*pi*tf.freq)))