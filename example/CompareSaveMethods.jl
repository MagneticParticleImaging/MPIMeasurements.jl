using MPIMeasurements
using FFTW
using Statistics

println("="^70)
println("MPI Data Storage Methods Comparison")
println("="^70)

config = (numSamples=1632, numChannels=3, numPeriods=500, numFrames=100, 
          numPeriodGrouping=5, selectedFrequencies=50)
testData = randn(Float32, config.numSamples, config.numChannels, config.numPeriods, config.numFrames)

println("\nMethod 1: Traditional (Full Time Domain)")
println("-"^70)
traditionalSize = sizeof(testData)
println("Storage: $(round(traditionalSize / 1024^2, digits=2)) MB")
println("Post-processing: Period grouping, FFT, frequency filtering needed")

println("\nMethod 2: Frequency Filtered During Acquisition")
println("-"^70)
mutable struct FilteredStorage <: StorageBuffer
    frequencyData::Vector{Any}
end
FilteredStorage() = FilteredStorage(Any[])
Base.push!(buffer::FilteredStorage, data) = (push!(buffer.frequencyData, data); (start=1, stop=size(data, 4)))
MPIMeasurements.sinks!(buffer::FilteredStorage, sinks::Vector{SinkBuffer}) = sinks

filteredBuffer = FilteredStorage()
frequencyIndices = collect(1:config.selectedFrequencies)
rfftBuffer = RFFTBuffer(filteredBuffer, frequencyIndices)
periodGroupingBuffer = PeriodGroupingBuffer(rfftBuffer, config.numPeriodGrouping)
push!(periodGroupingBuffer, testData)

filteredSize = sizeof(filteredBuffer.frequencyData[1])
println("Storage: $(round(filteredSize / 1024^2, digits=2)) MB")
println("Post-processing: None, ready for reconstruction")

savings = traditionalSize - filteredSize
savingsPercent = (1 - filteredSize / traditionalSize) * 100
compressionRatio = traditionalSize / filteredSize

println("\n"*"="^70)
println("Analysis")
println("="^70)
println("Space saved: $(round(savings / 1024^2, digits=2)) MB ($(round(savingsPercent, digits=2))%)")
println("Compression ratio: $(round(compressionRatio, digits=1))×")

positionsInScan = 3000
totalFrames = config.numFrames * positionsInScan
traditionalTotalSize = traditionalSize / config.numFrames * totalFrames
filteredTotalSize = filteredSize / config.numFrames * totalFrames
totalSavings = traditionalTotalSize - filteredTotalSize

println("\nFull 3D Scan Projection ($positionsInScan positions):")
println("  Traditional: $(round(traditionalTotalSize / 1024^3, digits=2)) GB")
println("  Filtered: $(round(filteredTotalSize / 1024^3, digits=2)) GB")
println("  Savings: $(round(totalSavings / 1024^3, digits=2)) GB")

archiveUploadSpeed = 100 * 1024^2
traditionalUploadTime = traditionalTotalSize / archiveUploadSpeed
filteredUploadTime = filteredTotalSize / archiveUploadSpeed
println("\nNetwork Transfer (100 MB/s):")
println("  Traditional: $(round(traditionalUploadTime / 60, digits=1)) min")
println("  Filtered: $(round(filteredUploadTime / 60, digits=1)) min")
println("  Time saved: $(round((traditionalUploadTime - filteredUploadTime) / 60, digits=1)) min")
println("="^70)
