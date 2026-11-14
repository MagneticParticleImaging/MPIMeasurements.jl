# Frames with a constant value per frame: frame i is filled with values[i]
constantFrames(values, dims = (2, 1, 1); T = Float32) = cat([fill(T(v), dims..., 1) for v in values]..., dims = 4)

@testset "Chainable buffers" begin
  @testset "FrameBuffer" begin
    seq = sequenceFromTOML(sequenceFixture("SimulatedScannerSequence.toml"))
    buffer = MPIMeasurements.FrameBuffer(seq)
    # samples x channels x periods x frames
    @test size(MPIMeasurements.read(buffer)) == (625, 1, 2, 3)
    @test MPIMeasurements.index(buffer) == 1

    buffer = MPIMeasurements.FrameBuffer(1, zeros(Float32, 2, 1, 1, 5))
    @test push!(buffer, constantFrames([1, 2])) == (start = 1, stop = 2)
    @test MPIMeasurements.index(buffer) == 3
    @test push!(buffer, constantFrames([3])) == (start = 3, stop = 3)
    @test MPIMeasurements.read(buffer)[1, 1, 1, :] == [1, 2, 3, 0, 0]

    # insert! overwrites frames at a given position ...
    @test MPIMeasurements.insert!(buffer, 2, constantFrames([7, 8])) == 3
    @test MPIMeasurements.read(buffer)[1, 1, 1, :] == [1, 7, 8, 0, 0]
    # ... or combines them with the existing content
    MPIMeasurements.insert!(+, buffer, 3, constantFrames([10, 20]))
    @test MPIMeasurements.read(buffer)[1, 1, 1, :] == [1, 7, 18, 20, 0]
    MPIMeasurements.insert!((new, old) -> new .* old, buffer, 1, constantFrames([3]))
    @test MPIMeasurements.read(buffer)[1, 1, 1, :] == [3, 7, 18, 20, 0]
    @test MPIMeasurements.sinks(buffer) == [buffer]
  end

  @testset "AverageBuffer" begin
    target = MPIMeasurements.FrameBuffer(1, zeros(Float32, 2, 1, 1, 3))
    avg = MPIMeasurements.AverageBuffer(target, 2, 1, 1, 2) # average blocks of 2 frames

    # Four frames -> two averaged frames
    @test push!(avg, constantFrames([1, 3, 5, 7])) == (start = 1, stop = 2)
    @test MPIMeasurements.read(target)[:, 1, 1, 1:2] == [2 6; 2 6]

    # A single frame is kept until the block is complete
    @test isnothing(push!(avg, constantFrames([10])))
    @test MPIMeasurements.index(target) == 3
    @test push!(avg, constantFrames([20])) == (start = 3, stop = 3)
    @test MPIMeasurements.read(target)[1, 1, 1, 3] == 15

    # Leftover frames are carried over to the next push
    target = MPIMeasurements.FrameBuffer(1, zeros(Float32, 2, 1, 1, 2))
    avg = MPIMeasurements.AverageBuffer(target, 2, 1, 1, 2)
    @test push!(avg, constantFrames([1, 2, 4])) == (start = 1, stop = 1)
    @test MPIMeasurements.read(target)[1, 1, 1, :] == [1.5, 0]
    @test push!(avg, constantFrames([8])) == (start = 2, stop = 2)
    @test MPIMeasurements.read(target)[1, 1, 1, :] == [1.5, 6]

    # Constructed from a sequence: two frame averages of 625 x 1 x 2
    seq = sequenceFromTOML(sequenceFixture("SimulatedScannerSequence.toml"))
    avg = MPIMeasurements.AverageBuffer(MPIMeasurements.FrameBuffer(seq), seq)
    @test size(avg.buffer) == (625, 1, 2, 2)
    @test MPIMeasurements.sinks(avg) == [avg.target]
    @test MPIMeasurements.sink(avg, MPIMeasurements.FrameBuffer) === avg.target
    @test isnothing(MPIMeasurements.sink(avg, MPIMeasurements.DeviceBuffer))
    @test isempty(MPIMeasurements.sinks(avg, MPIMeasurements.DeviceBuffer))
  end

  @testset "DriveFieldBuffer" begin
    buffer = MPIMeasurements.DriveFieldBuffer(1, zeros(ComplexF64, 1, 1, 1, 3), UnusedControlSequence())
    @test push!(buffer, constantFrames([1im, 2], (1, 1, 1), T = ComplexF64)) == (start = 1, stop = 2)
    @test MPIMeasurements.index(buffer) == 3
    MPIMeasurements.insert!(+, buffer, 2, constantFrames([1 + 1im, 5], (1, 1, 1), T = ComplexF64))
    @test vec(MPIMeasurements.read(buffer)) == [1im, 3 + 1im, 5]
  end

  @testset "TemperatureBuffer" begin
    sensor = DummyTemperatureSensor(deviceID = "temp", params = DummyTemperatureSensorParams(),
      dependencies = Dict{String, Union{Device, Missing}}())
    buffer = MPIMeasurements.TemperatureBuffer(sensor, 4)
    @test size(MPIMeasurements.read(buffer)) == (50, 4) # the dummy sensor has 50 channels

    MPIMeasurements.insert!(buffer, fill(1.5f0, 50), 1, 1)
    MPIMeasurements.insert!(buffer, fill(2.5, 50), 2, 2)
    MPIMeasurements.insert!(buffer, fill(3.5u"°C", 50), 3, 3)
    @test MPIMeasurements.read(buffer)[:, 1:3] == repeat(Float32[1.5 2.5 3.5], 50)
    @test eltype(MPIMeasurements.read(buffer)) == Float32

    # update! reads the sensor (30 °C + channel index + noise)
    MPIMeasurements.update!(buffer, 4, 4)
    @test all(25 .< MPIMeasurements.read(buffer)[:, 4] .< 90)
  end

  @testset "Sink lookup through a splitter" begin
    # FrameSplitterBuffer needs a DAQ to split frames, but not to look up its sinks
    frames = MPIMeasurements.FrameBuffer(1, zeros(Float32, 1, 1, 1, 1))
    fields = MPIMeasurements.DriveFieldBuffer(1, zeros(ComplexF64, 1, 1, 1, 1), UnusedControlSequence())
    daq = getDAQ(simulatedScanner)
    splitter = MPIMeasurements.FrameSplitterBuffer(daq, MPIMeasurements.StorageBuffer[frames, fields])
    @test MPIMeasurements.sinks(splitter) == [frames, fields]
    @test MPIMeasurements.sink(splitter, MPIMeasurements.FrameBuffer) === frames
    @test MPIMeasurements.sink(splitter, MPIMeasurements.DriveFieldBuffer) === fields
    @test_throws ErrorException MPIMeasurements.sink(splitter, MPIMeasurements.SequenceBuffer) # ambiguous
  end

  @testset "Memory-mapped FrameBuffer" begin
    # Mapped files stay open while the arrays are alive, which blocks removing them on
    # Windows, so the directory is left to the cleanup of mktempdir at exit
    protocol = TempDirProtocol(mktempdir())
    seq = sequenceFromTOML(sequenceFixture("SimulatedScannerSequence.toml"))
    buffer = MPIMeasurements.FrameBuffer(protocol, "frames.bin", seq)
    @test size(MPIMeasurements.read(buffer)) == (625, 1, 2, 3)
    @test all(iszero, MPIMeasurements.read(buffer))
    push!(buffer, fill(1.0f0, 625, 1, 2, 1))
    MPIMeasurements.Mmap.sync!(MPIMeasurements.read(buffer))

    # The data is backed by the file and can be mapped again
    mapped = MPIMeasurements.mmap(protocol, "frames.bin", Float32)
    @test size(mapped) == (625, 1, 2, 3)
    @test all(mapped[:, :, :, 1] .== 1)
    @test all(iszero, mapped[:, :, :, 2:3])
  end

  @testset "ProtocolMeasState" begin
    meas = MPIMeasurements.ProtocolMeasState()
    bg = MPIMeasurements.FrameBuffer(1, constantFrames([1, 2]))
    fg = MPIMeasurements.FrameBuffer(1, constantFrames([3, 4, 5]))
    push!(meas, MPIMeasurements.SinkBuffer[bg], isBGMeas = true)
    push!(meas, MPIMeasurements.SinkBuffer[fg])

    data = MPIMeasurements.read(meas, MPIMeasurements.FrameBuffer)
    @test size(data) == (2, 1, 1, 5)
    @test data[1, 1, 1, :] == [1, 2, 3, 4, 5]
    @test isnothing(MPIMeasurements.read(meas, MPIMeasurements.TemperatureBuffer))
    @test MPIMeasurements.measIsBGFrame(meas) == [true, true, false, false, false]
    @test MPIMeasurements.measIsBGFrame(meas, 4, 1) == [true, false, false, false, false]

    # All buffers of one measurement step must hold the same number of frames
    other = MPIMeasurements.FrameBuffer(1, constantFrames([1]))
    push!(meas, MPIMeasurements.SinkBuffer[fg, other])
    @test_throws ErrorException MPIMeasurements.measIsBGFrame(meas)
  end
end
