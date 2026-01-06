using MPIMeasurements
using FFTW
using Statistics

println("="^70)
println("Frequency Filtering Pipeline Visualization")
println("="^70)

numSamples, numChannels, numPeriods, numFrames = 64, 3, 12, 4
numPeriodGrouping, selectedFrequencies = 3, [1, 3, 5, 7, 9, 11, 13, 15]

t = range(0, 2π, length=numSamples)
signal = sin.(t .* 3) .+ 0.5 .* sin.(t .* 7) .+ 0.2 .* randn(numSamples)
inputData = zeros(Float32, numSamples, numChannels, numPeriods, numFrames)
for c in 1:numChannels, p in 1:numPeriods, f in 1:numFrames
    inputData[:, c, p, f] .= signal .* (1 + 0.1 * randn())
end

println("\n"*"="^70)
println("Stage 1: Time Domain Input")
println("="^70)
println("Shape: $(size(inputData))")
println("Memory: $(sizeof(inputData)) bytes")
println("Type: $(eltype(inputData))")

println("\n"*"="^70)
println("Stage 2: Period Grouping (×$numPeriodGrouping)")
println("="^70)
tmp = permutedims(inputData, (1, 3, 2, 4))
tmp2 = reshape(tmp, numSamples * numPeriodGrouping, div(numPeriods, numPeriodGrouping), numChannels, numFrames)
groupedData = permutedims(tmp2, (1, 3, 2, 4))
println("Shape: $(size(inputData)) → $(size(groupedData))")
println("Memory: $(sizeof(groupedData)) bytes")

println("\n"*"="^70)
println("Stage 3: Real FFT")
println("="^70)
fftData = rfft(groupedData, 1)
numFrequencies = size(fftData, 1)
println("Shape: $(size(groupedData)) → $(size(fftData))")
println("Memory: $(sizeof(fftData)) bytes")
println("Type: $(eltype(fftData))")

spectrum = abs.(fftData[:, 1, 1, 1])
topFreqs = sortperm(spectrum, rev=true)[1:3]
println("Top frequencies: $(topFreqs)")

println("\n"*"="^70)
println("Stage 4: Frequency Selection")
println("="^70)
filteredData = fftData[selectedFrequencies, :, :, :]
println("Shape: $(size(fftData)) → $(size(filteredData))")
println("Memory: $(sizeof(fftData)) → $(sizeof(filteredData)) bytes")
println("Reduction: $(round((1 - sizeof(filteredData) / sizeof(fftData)) * 100, digits=1))%")

println("\n"*"="^70)
println("Stage 5: MDF Storage")
println("="^70)
println("Shape: $(size(filteredData))")
println("Type: $(eltype(filteredData))")
println("MDF metadata: isFourierTransformed=true, isFrequencySelection=true")

totalReduction = (1 - sizeof(filteredData) / sizeof(inputData)) * 100
compressionRatio = sizeof(inputData) / sizeof(filteredData)

println("\n"*"="^70)
println("Pipeline Summary")
println("="^70)
println("Original: $(sizeof(inputData)) bytes")
println("Filtered: $(sizeof(filteredData)) bytes")
println("Reduction: $(round(totalReduction, digits=2))%")
println("Compression: $(round(compressionRatio, digits=1))×")
println("="^70)
