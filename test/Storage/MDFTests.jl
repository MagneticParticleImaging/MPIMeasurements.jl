const DateTime = MPIMeasurements.Dates.DateTime

@testset "MDF" begin
  MF = MPIMeasurements.MPIFiles
  seq = sequenceFromTOML(sequenceFixture("SimulatedScannerSequence.toml"))
  # 625 samples x 1 channel x 2 periods x 3 frames with distinct values
  data = reshape(Float32.(1:(625 * 1 * 2 * 3)), 625, 1, 2, 3)

  @testset "prepareAsMDF" begin
    mdf = MPIMeasurements.prepareAsMDF(data, simulatedScanner, seq)
    @test MF.measData(mdf) == data
    @test MF.measIsBackgroundFrame(mdf) == [false, false, false]
    @test MF.measIsBackgroundCorrected(mdf) == false
    @test MF.measIsFourierTransformed(mdf) == false
    @test isnothing(MF.measTemperatures(mdf))

    # Acquisition: 4 block averages x 2 frame averages
    @test MF.acqNumAverages(mdf) == 8
    @test MF.acqNumFrames(mdf) == 3
    @test MF.acqNumPeriodsPerFrame(mdf) == 2
    @test isnothing(MF.acqOffsetField(mdf))

    # Drive field: one channel, divider 5000 at 125 MHz -> 40 µs cycle
    @test MF.dfBaseFrequency(mdf) == 125.0e6
    @test MF.dfCycle(mdf) ≈ 40e-6
    @test MF.dfDivider(mdf) == reshape([5000], 1, 1)
    @test MF.dfNumChannels(mdf) == 1
    @test MF.dfStrength(mdf) == reshape([0.012], 1, 1, 1)
    @test MF.dfPhase(mdf) == reshape([0.0], 1, 1, 1)
    @test MF.dfWaveform(mdf) == reshape(["sine"], 1, 1)

    # Receiver: 15.625 MHz * 40 µs = 625 samples
    @test MF.rxBandwidth(mdf) == 7.8125e6
    @test MF.rxNumChannels(mdf) == 1
    @test MF.rxNumSamplingPoints(mdf) == 625
    @test MF.rxUnit(mdf) == "V"
    @test MF.rxDataConversionFactor(mdf) == reshape([1.0, 0.0], 2, 1)
    @test isnothing(MF.rxTransferFunction(mdf)) # no transfer function configured

    # Background frames are passed through
    mdf = MPIMeasurements.prepareAsMDF(data, simulatedScanner, seq, [true, false, false])
    @test MF.measIsBackgroundFrame(mdf) == [true, false, false]
  end

  @testset "fillMDFMeasurement" begin
    temps = reshape(Float32.(1:6), 2, 3)
    applied = fill(ComplexF64(1, 2), 1, 1, 2, 3)

    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFMeasurement(mdf, data, zeros(Bool, 3); temperatures = temps, drivefield = applied, applied = applied)
    @test MF.measTemperatures(mdf) == temps
    @test MF.measObservedDriveField(mdf) == applied
    @test MF.measAppliedDriveField(mdf) == applied

    # Values that are not passed are left alone
    mdf = MF.MDFv2InMemory()
    MF.measTemperatures(mdf, temps)
    MF.measObservedDriveField(mdf, applied)
    MPIMeasurements.fillMDFMeasurement(mdf, data, zeros(Bool, 3))
    @test MF.measObservedDriveField(mdf) == applied
    @test MF.measTemperatures(mdf) == temps

    # Without background data all frames are foreground frames
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFMeasurement(mdf, seq, data, nothing)
    @test MF.measIsBackgroundFrame(mdf) == [false, false, false]
    @test MF.measData(mdf) == data

    # Background frames are prepended to the data
    bg = fill(-1.0f0, 625, 1, 2, 2)
    bgField = fill(ComplexF64(0, 1), 1, 1, 2, 2)
    mdf = MF.MDFv2InMemory()
    bgTemps = fill(-1.0f0, 2, 2)
    MPIMeasurements.fillMDFMeasurement(mdf, seq, data, bg; temperatures = temps, bgTemperatures = bgTemps,
      drivefield = applied, bgDriveField = bgField, applied = applied, bgTransmit = bgField)
    @test MF.measIsBackgroundFrame(mdf) == [true, true, false, false, false]
    @test size(MF.measData(mdf)) == (625, 1, 2, 5)
    @test all(MF.measData(mdf)[:, :, :, 1:2] .== -1)
    @test MF.measData(mdf)[:, :, :, 3:5] == data
    @test MF.measObservedDriveField(mdf)[:, :, :, 1:2] == bgField
    @test MF.measObservedDriveField(mdf)[:, :, :, 3:5] == applied
    @test size(MF.measAppliedDriveField(mdf), 4) == 5
    @test MF.measTemperatures(mdf) == hcat(bgTemps, temps)
    # Temperatures that do not cover the background frames are rejected
    @test_throws ArgumentError MPIMeasurements.fillMDFMeasurement(MF.MDFv2InMemory(), seq, data, bg; temperatures = temps)
    @test_throws "must be given together" MPIMeasurements.fillMDFMeasurement(MF.MDFv2InMemory(), seq, data, bg; temperatures = temps)
    @test_throws "must be given together" MPIMeasurements.fillMDFMeasurement(MF.MDFv2InMemory(), seq, data, bg; bgTemperatures = bgTemps)
  end

  @testset "fillMDFCalibration" begin
    grid = MF.RegularGridPositions([2, 3, 1], [2.0, 3.0, 1.0] .* u"mm", [0.0, 0.5, 0.0] .* u"mm")
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFCalibration(mdf, grid)
    @test MF.calibMethod(mdf) == "robot"
    @test MF.calibSize(mdf) == [2, 3, 1]
    @test MF.calibFov(mdf) ≈ [0.002, 0.003, 0.001]
    @test MF.calibFovCenter(mdf) ≈ [0.0, 0.0005, 0.0]
    @test isnothing(MF.calibDeltaSampleSize(mdf))

    # deltaSampleSize is stored in meters
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFCalibration(mdf, grid; deltaSampleSize = [0.001, 0.002, 0.0005] .* u"m")
    @test MF.calibDeltaSampleSize(mdf) == [0.001, 0.002, 0.0005]

    # Hybrid calibration from offset fields on a 2 x 2 x 1 grid (last dimension: x, y, z)
    offsets = zeros(2, 2, 1, 3)
    offsets[2, :, :, 1] .= 0.01
    offsets[:, 2, :, 2] .= 0.02
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFCalibration(mdf, offsets)
    @test MF.calibMethod(mdf) == "hybrid"
    @test MF.calibSize(mdf) == [2, 2, 1]
    @test MF.calibFov(mdf) ≈ [0.01, 0.02, 0.0]
    @test MF.calibFovCenter(mdf) ≈ [0.005, 0.01, 0.0]
    @test size(MF.calibOffsetFields(mdf)) == (3, 4)
    @test MF.calibOffsetFields(mdf)[:, 4] ≈ [0.01, 0.02, 0.0] # position (2, 2)
    @test MF.acqGradient(mdf) == reshape([1.0 0 0; 0 1 0; 0 0 1], 3, 3, 1, 1)
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFCalibration(mdf, offsets; deltaSampleSize = [0.001, 0.002, 0.0005] .* u"m")
    @test MF.calibDeltaSampleSize(mdf) == [0.001, 0.002, 0.0005]

    # Other position types are not supported and only produce a warning
    mdf = MF.MDFv2InMemory()
    @test_logs (:warn, r"not implemented") MPIMeasurements.fillMDFCalibration(mdf, MF.ArbitraryPositions(grid))
    @test isnothing(mdf.calibration)
  end

  @testset "Scanner, tracer, study and experiment" begin
    mdf = MF.MDFv2InMemory()
    MPIMeasurements.fillMDFScanner(mdf, simulatedScanner)
    @test MF.scannerBoreSize(mdf) ≈ 1.337
    @test MF.scannerFacility(mdf) == "My awesome institute"
    @test MF.scannerManufacturer(mdf) == "Me, Myself and I"
    @test MF.scannerName(mdf) == "TestSimpleSimulatedScanner"
    @test MF.scannerTopology(mdf) == "FFL"
    @test MF.scannerOperator(mdf) == "default"
    # An operator that is already set is kept
    MF.scannerOperator(mdf, "Alice")
    MPIMeasurements.fillMDFScanner(mdf, simulatedScanner)
    @test MF.scannerOperator(mdf) == "Alice"

    MPIMeasurements.fillMDFTracer(mdf)
    @test MF.tracerSolute(mdf) == ["Fe"]
  end

  @testset "saveasMDF" begin
    mktempdir() do dir
      store = MF.MDFDatasetStore(dir)
      newMDF() = (mdf = MF.MDFv2InMemory(); MF.studyName(mdf, "UnitTest"); MF.studyTime(mdf, DateTime(2024, 1, 2, 3, 4, 5)); mdf)

      mdf = newMDF()
      filename = MF.saveasMDF(store, simulatedScanner, seq, data, zeros(Bool, 3), mdf)
      @test isfile(filename)
      @test MF.studyName(mdf) == "UnitTest"
      @test MF.experimentNumber(mdf) == 1
      @test MF.experimentName(mdf) == "default"
      @test MF.scannerName(mdf) == "TestSimpleSimulatedScanner"
      @test MF.acqNumFrames(mdf) == 3

      # Background data is stored in front of the foreground frames
      mdf = newMDF()
      filename = MF.saveasMDF(store, simulatedScanner, seq, data, mdf; bgdata = zeros(Float32, 625, 1, 2, 1))
      @test isfile(filename)
      @test MF.experimentNumber(mdf) == 2
      @test MF.acqNumFrames(mdf) == 4
      @test MF.measIsBackgroundFrame(mdf) == [true, false, false, false]

      # System matrices go to the calibration folder
      grid = MF.RegularGridPositions([3, 1, 1], [3.0, 1.0, 1.0] .* u"mm", [0.0, 0.0, 0.0] .* u"mm")
      mdf = MF.MDFv2InMemory()
      filename = MF.saveasMDF(store, simulatedScanner, seq, data, grid, zeros(Bool, 3), mdf; storeAsSystemMatrix = true)
      @test isfile(filename)
      @test MF.calibSize(mdf) == [3, 1, 1]
      @test MF.calibMethod(mdf) == "robot"

      # Without study name and time, defaults are used
      mdf = MF.MDFv2InMemory()
      @test isfile(MF.saveasMDF(store, simulatedScanner, seq, data, zeros(Bool, 3), mdf))
      @test MF.studyName(mdf) == "n.a."
      @test MF.studyTime(mdf) isa DateTime
      mdf = MF.MDFv2InMemory()
      @test isfile(MF.saveasMDF(store, simulatedScanner, seq, data, mdf; bgdata = zeros(Float32, 625, 1, 2, 1)))
      @test MF.studyTime(mdf) isa DateTime
      mdf = MF.MDFv2InMemory()
      @test isfile(MF.saveasMDF(store, simulatedScanner, seq, data, grid, zeros(Bool, 3), mdf))
      @test MF.studyTime(mdf) isa DateTime
    end
  end
end
