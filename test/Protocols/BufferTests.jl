using Test
using FFTW
using Statistics
using MPIMeasurements

mutable struct MockStorageBuffer <: StorageBuffer
    data::Vector{Any}
end
MockStorageBuffer() = MockStorageBuffer(Any[])
Base.push!(buffer::MockStorageBuffer, data) = (push!(buffer.data, data); return (start=1, stop=size(data, 4)))
MPIMeasurements.sinks!(buffer::MockStorageBuffer, sinks::Vector{SinkBuffer}) = sinks

@testset "PeriodGroupingBuffer Tests" begin
    @testset "Basic period grouping with numGrouping=2" begin
        mockTarget = MockStorageBuffer()
        buffer = PeriodGroupingBuffer(mockTarget, 2)
        testData = randn(Float32, 8, 3, 4, 2)
        push!(buffer, testData)
        @test length(mockTarget.data) == 1
        @test size(mockTarget.data[1]) == (16, 3, 2, 2)
    end
    
    @testset "Period grouping with numGrouping=1 (pass-through)" begin
        mockTarget = MockStorageBuffer()
        buffer = PeriodGroupingBuffer(mockTarget, 1)
        testData = randn(Float32, 8, 3, 4, 2)
        push!(buffer, testData)
        @test size(mockTarget.data[1]) == size(testData)
        @test mockTarget.data[1] ≈ testData
    end
    
    @testset "Period grouping with non-divisible periods should error" begin
        mockTarget = MockStorageBuffer()
        buffer = PeriodGroupingBuffer(mockTarget, 3)
        testData = randn(Float32, 8, 3, 5, 2)
        @test_throws ErrorException push!(buffer, testData)
    end
    
    @testset "Period grouping matches MPIFiles getMeasurements logic" begin
        mockTarget = MockStorageBuffer()
        numPeriodGrouping, numSamples, numChannels, numPeriods, numFrames = 3, 12, 3, 9, 4
        buffer = PeriodGroupingBuffer(mockTarget, numPeriodGrouping)
        testData = randn(Float32, numSamples, numChannels, numPeriods, numFrames)
        push!(buffer, testData)
        result = mockTarget.data[1]
        
        @test size(result) == (numSamples * numPeriodGrouping, numChannels, div(numPeriods, numPeriodGrouping), numFrames)
        
        tmp = permutedims(testData, (1, 3, 2, 4))
        tmp2 = reshape(tmp, numSamples * numPeriodGrouping, div(numPeriods, numPeriodGrouping), numChannels, numFrames)
        expected = permutedims(tmp2, (1, 3, 2, 4))
        @test result ≈ expected
    end
end

@testset "RFFTBuffer Tests" begin
    @testset "Basic RFFT without frequency selection" begin
        mockTarget = MockStorageBuffer()
        buffer = RFFTBuffer(mockTarget, nothing)
        testData = randn(Float32, 16, 3, 2, 4)
        push!(buffer, testData)
        @test length(mockTarget.data) == 1
        @test size(mockTarget.data[1]) == (9, 3, 2, 4)
        @test eltype(mockTarget.data[1]) <: Complex
    end
    
    @testset "RFFT with frequency selection" begin
        mockTarget = MockStorageBuffer()
        buffer = RFFTBuffer(mockTarget, [1, 3, 5, 7])
        testData = randn(Float32, 16, 3, 2, 4)
        push!(buffer, testData)
        @test size(mockTarget.data[1]) == (4, 3, 2, 4)
    end
    
    @testset "RFFT matches FFTW.rfft behavior" begin
        mockTarget = MockStorageBuffer()
        buffer = RFFTBuffer(mockTarget, nothing)
        testData = randn(Float32, 32, 2, 3, 5)
        push!(buffer, testData)
        @test mockTarget.data[1] ≈ rfft(testData, 1)
    end
    
    @testset "RFFT with frequency selection matches indexing" begin
        mockTarget = MockStorageBuffer()
        frequencyMask = [2, 4, 6, 8, 10]
        buffer = RFFTBuffer(mockTarget, frequencyMask)
        testData = randn(Float32, 32, 2, 3, 5)
        push!(buffer, testData)
        @test mockTarget.data[1] ≈ rfft(testData, 1)[frequencyMask, :, :, :]
    end
end

@testset "Combined PeriodGrouping + RFFT Pipeline" begin
    @testset "Period grouping followed by RFFT" begin
        mockTarget = MockStorageBuffer()
        rfftBuffer = RFFTBuffer(mockTarget, nothing)
        periodBuffer = PeriodGroupingBuffer(rfftBuffer, 2)
        testData = randn(Float32, 16, 3, 4, 2)
        push!(periodBuffer, testData)
        @test length(mockTarget.data) == 1
        @test size(mockTarget.data[1]) == (17, 3, 2, 2)
        @test eltype(mockTarget.data[1]) <: Complex
    end
    
    @testset "Period grouping + RFFT + frequency selection" begin
        mockTarget = MockStorageBuffer()
        frequencyMask = [1, 5, 9, 13]
        rfftBuffer = RFFTBuffer(mockTarget, frequencyMask)
        periodBuffer = PeriodGroupingBuffer(rfftBuffer, 3)
        testData = randn(Float32, 24, 3, 9, 4)
        push!(periodBuffer, testData)
        result = mockTarget.data[1]
        @test size(result) == (4, 3, 3, 4)
        
        tmp = permutedims(testData, (1, 3, 2, 4))
        tmp2 = reshape(tmp, 72, 3, 3, 4)
        grouped = permutedims(tmp2, (1, 3, 2, 4))
        expected = rfft(grouped, 1)[frequencyMask, :, :, :]
        @test result ≈ expected
    end
end
