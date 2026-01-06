using MPIMeasurements
using FFTW
using Statistics

println("="^70)
println("Frequency Filtering Demonstration")
println("="^70)

numSamples, numChannels, numPeriods, numFrames = 1632, 3, 500, 100
numPeriodGrouping = 5

function createSyntheticMPIData(samples, channels, periods, frames)
    data = zeros(Float32, samples, channels, periods, frames)
    for freq in [1, 2, 3, 5, 7, 11]
        amplitude = 1.0 / freq
        for t in 1:samples
            data[t, :, :, :] .+= amplitude * sin(2π * freq * (t-1) / samples)
        end
    end
    data .+= 0.1f0 * randn(Float32, size(data)...)
    return data
end

originalData = createSyntheticMPIData(numSamples, numChannels, numPeriods, numFrames)
originalSize = sizeof(originalData)
println("\nOriginal: $(size(originalData)), $(round(originalSize / 1024^2, digits=2)) MB")

println("\nApplying frequency filtering...")

selectedFrequencies = 1:50
numFrequenciesAfterGrouping = div(numSamples * numPeriodGrouping, 2) + 1
println("  Selected: $(length(selectedFrequencies)) / $numFrequenciesAfterGrouping frequencies")

mutable struct CaptureBuffer <: StorageBuffer
    data::Vector{Any}
end
CaptureBuffer() = CaptureBuffer(Any[])
Base.push!(buffer::CaptureBuffer, data) = (push!(buffer.data, data); (start=1, stop=size(data, 4)))
MPIMeasurements.sinks!(buffer::CaptureBuffer, sinks::Vector{SinkBuffer}) = sinks

captureBuffer = CaptureBuffer()
rfftBuffer = RFFTBuffer(captureBuffer, collect(selectedFrequencies))
periodGroupingBuffer = PeriodGroupingBuffer(rfftBuffer, numPeriodGrouping)
push!(periodGroupingBuffer, originalData)

filteredData = captureBuffer.data[1]
filteredSize = sizeof(filteredData)

println("\nFiltered: $(size(filteredData)), $(round(filteredSize / 1024^2, digits=2)) MB")
reductionPercent = (1 - filteredSize / originalSize) * 100
compressionRatio = originalSize / filteredSize

println("\n"*"="^70)
println("Results")
println("="^70)
println("Data reduction: $(round(reductionPercent, digits=2))%")
println("Compression ratio: $(round(compressionRatio, digits=1))×")
println("Storage saved: $(round((originalSize - filteredSize) / 1024^2, digits=2)) MB")

fullSpectrum = abs.(rfft(originalData[:, 1, 1, 1]))
filteredSpectrum = abs.(filteredData[:, 1, 1, 1])
println("\nSpectrum analysis:")
println("  Full length: $(length(fullSpectrum)), strongest at $(argmax(fullSpectrum))")
println("  Filtered length: $(length(filteredSpectrum)), strongest at $(argmax(filteredSpectr um))")
println("="^70)

println("  Filtered data shape: $(size(filteredData))")
println("  Filtered data size: $(round(filteredSize / 1024^2, digits=2)) MB")
println("  Data type: $(eltype(filteredData))")

# ============================================================================
# Part 3: Calculate Savings
# ============================================================================

println("\n[3/4] Analyzing storage efficiency...")

reductionPercent = (1 - filteredSize / originalSize) * 100
compressionRatio = originalSize / filteredSize

println("  ✓ Data reduction: $(round(reductionPercent, digits=2))%")
println("  ✓ Compression ratio: $(round(compressionRatio, digits=1))×")
println("  ✓ Storage saved: $(round((originalSize - filteredSize) / 1024^2, digits=2)) MB")

# ============================================================================
# Part 4: Frequency Spectrum Analysis
# ============================================================================

println("\n[4/4] Frequency spectrum analysis...")

# Compute full spectrum for comparison
fullSpectrum = rfft(originalData[:, 1, 1, 1])  # First channel, first period, first frame
fullSpectrumMagnitude = abs.(fullSpectrum)

# Filtered spectrum (what we actually store)
filteredSpectrum = filteredData[:, 1, 1, 1]  # Same selection
filteredSpectrumMagnitude = abs.(filteredSpectrum)

println("  Full spectrum length: $(length(fullSpectrum))")
println("  Filtered spectrum length: $(length(filteredSpectrum))")
println("  Strongest at: $(argmax(filteredSpectrum))")
println("="^70)
