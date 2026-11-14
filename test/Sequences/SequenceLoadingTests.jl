@testset "Loading from TOML" begin
  @testset "Existing test configuration (1DSequence)" begin
    configDir_ = joinpath(testConfigDir, "TestDeviceWorkingScanner")
    seq = Sequence(configDir_, "1DSequence")
    @test seq == sequenceFromTOML(joinpath(configDir_, "Sequences", "1DSequence.toml"))
    @test seq == Sequence(joinpath(configDir_, "Sequences", "1DSequence.toml"))
    @test_throws ErrorException Sequence(configDir_, "DoesNotExist")

    @test name(seq) == "1DSequence"
    @test description(seq) == "Precise description."
    @test targetScanner(seq) == "testscanner"
    @test baseFrequency(seq) == 125.0u"MHz"
    @test length(seq) == 2
    @test sort(collect(keys(seq))) == ["df", "ff"]

    # Drive field: one channel with divider 4800 at 125 MHz
    @test dfNumChannels(seq) == 1
    @test dfDivider(seq) == reshape([4800//1], 1, 1)
    @test dfSamplesPerCycle(seq) == 4800
    @test dfCycle(seq) ≈ 4800 / 125.0e6 * u"s"
    @test dfStrength(seq) == reshape([0.02u"T"], 1, 1, 1)
    @test dfPhase(seq) == reshape([0.0u"rad"], 1, 1, 1)
    @test dfWaveform(seq) == reshape([WAVEFORM_SINE], 1, 1)

    # 15.625 MHz sampling rate * 38.4 µs cycle
    @test rxBandwidth(seq) == 7.8125u"MHz"
    @test rxSamplingRate(seq) == 15.625u"MHz"
    @test rxNumSamplingPoints(seq) == 600
    @test rxNumSamplesPerPeriod(seq) == 600
    @test id.(rxChannels(seq)) == ["rx_main", "rx_side"]
    @test rxNumChannels(seq) == 2

    # The continuous offset channel spans 18240000/4800 = 3800 periods in steps of
    # 3648000/4800 = 760 periods, i.e. 5 patches
    @test acqNumPeriodsPerFrame(seq) == 3800
    @test acqNumPeriodsPerPatch(seq) == 760
    @test acqNumPatches(seq) == 5

    ffx = seq["ff"]["ffx"]
    @test ffx isa ContinuousElectricalChannel
    expected = [0.4 + 0.2 * sin(2π * p / 5) for p in 0:4] .* u"A"
    @test MPIMeasurements.values(ffx) ≈ expected

    @test needsControl(seq)
    @test needsDecoupling(seq)
    @test needsControlOrDecoupling(seq)
  end

  @testset "Outdated sequence files are rejected" begin
    # Several sequence files in config/ still use the old format, e.g. a `triggered`
    # entry in [General] or channels without a `type`. Loading them must fail loudly.
    dict = loadFixtureDict("MultiChannelSequence.toml")
    dict["General"]["triggered"] = false
    @test_throws Exception sequenceFromDict(dict)

    dict = loadFixtureDict("MultiChannelSequence.toml")
    delete!(dict["Fields"]["df"]["chanx"], "type")
    @test_throws ErrorException sequenceFromDict(dict)
  end

  @testset "Structure of the multi-channel fixture" begin
    seq = sequenceFromTOML(sequenceFixture("MultiChannelSequence.toml"))
    @test name(seq) == "MultiChannelSequence"
    @test targetScanner(seq) == "TestScanner"
    @test sort(collect(keys(seq))) == ["df", "ff", "robot"]

    df = seq["df"]
    @test df isa MagneticField
    @test MPIMeasurements.id(df) == "df"
    # Channels within a field are sorted by their ID
    @test collect(keys(df)) == ["chanx", "chany", "chanz"]
    @test safeStartInterval(df) == 1.0u"s"
    @test safeTransitionInterval(df) == 0.25u"s"
    @test safeEndInterval(df) == 2.0u"s"
    @test safeErrorInterval(df) == 0.1u"s"
    @test MPIMeasurements.control(df)
    @test !MPIMeasurements.decouple(df)

    # Defaults of the field intervals
    robot = seq["robot"]
    @test safeStartInterval(robot) == 0.5u"s"
    @test safeTransitionInterval(robot) == 0.5u"s"
    @test safeEndInterval(robot) == 0.5u"s"
    @test safeErrorInterval(robot) == 0.5u"s"
    @test !MPIMeasurements.control(robot)

    chanx = df["chanx"]
    @test chanx isa PeriodicElectricalChannel
    @test offset(chanx) == 1.5u"mT"
    @test collect(keys(chanx)) == ["c1", "c2"]
    @test divider(chanx["c1"]) == 4800
    @test amplitude(chanx["c1"]) == 0.010u"T"
    @test phase(chanx["c1"]) == 0.0u"rad"
    @test waveform(chanx["c1"]) == WAVEFORM_SINE
    @test divider(chanx["c2"]) == 4864
    @test amplitude(chanx["c2"]) == 5.0u"mT"
    @test phase(chanx["c2"]) ≈ (π / 2)u"rad" # "cos"
    @test waveform(chanx["c2"]) == WAVEFORM_TRIANGLE
    @test phase(df["chany"]["c1"]) ≈ (1.0π)u"rad" # "-sin"
    @test waveform(df["chany"]["c1"]) == WAVEFORM_SINE # default

    chanz = df["chanz"]
    @test !MPIMeasurements.isDfChannel(chanz)
    @test !chanz.dcEnabled
    @test offset(chanz) == 0.5u"A"
    @test amplitude(chanz["c1"]) == 1.0u"A"

    ffx = seq["ff"]["ffx"]
    @test ffx isa StepwiseElectricalChannel
    @test MPIMeasurements.values(ffx) == [-1.0, 0.0, 1.0, 2.0] .* u"mT"
    @test MPIMeasurements.enableValues(ffx) == [true, false, true, true]

    ffy = seq["ff"]["ffy"]
    @test ffy isa ContinuousElectricalChannel
    @test ffy.divider == 1459200
    @test ffy.dividerSteps == 364800
    @test ffy.waveform == WAVEFORM_SAWTOOTH_RISING

    rob = seq["robot"]["rob"]
    @test rob isa StepwiseMechanicalTranslationChannel
    @test rob.speed ≈ 10.0u"mm/s"
    @test rob.positions == [0.0, 10.0, 20.0] .* u"mm"
    @test stepPriority(rob) == 1
    @test preStepPause(rob) == 0.5u"s"
    @test postStepPause(rob) == 0.25u"s"

    @test id.(rxChannels(seq)) == ["rx1", "rx2"]
    @test acqNumFrames(seq) == 10
    @test acqNumAverages(seq) == 3
    @test acqNumFrameAverages(seq) == 2
  end

  @testset "Dict and TOML round trips" begin
    seq = sequenceFromTOML(sequenceFixture("MultiChannelSequence.toml"))

    dict = MPIMeasurements.toDict(seq)
    @test dict["General"]["name"] == "MultiChannelSequence"
    @test uparse(dict["General"]["baseFrequency"]) == 125.0u"MHz"
    @test dict["Acquisition"]["channels"] == ["rx1", "rx2"]
    @test dict["Fields"]["df"]["chanx"]["type"] == "PeriodicElectricalChannel"
    @test dict["Fields"]["df"]["chanx"]["c2"]["type"] == "PeriodicElectricalComponent"
    @test dict["Fields"]["df"]["chanx"]["c2"]["waveform"] == "triangle"
    @test dict["Fields"]["df"]["chanx"]["c1"]["divider"] == Dict("num" => 4800, "den" => 1)

    seq2 = sequenceFromDict(dict)
    @test seq2 == seq
    @test hash(seq2) == hash(seq)

    mktempdir() do dir
      file = joinpath(dir, "roundtrip.toml")
      MPIMeasurements.toTOML(file, seq)
      seq3 = sequenceFromTOML(file)
      @test seq3 == seq
    end

    # Equality is structural, so changing a single value breaks it
    seq4 = sequenceFromTOML(sequenceFixture("MultiChannelSequence.toml"))
    amplitude!(seq4["df"]["chanx"], "c1", 0.011u"T")
    @test seq4 != seq
    @test seq4["df"] != seq["df"]
    @test seq4["df"]["chanx"] != seq["df"]["chanx"]
    @test seq4["ff"] == seq["ff"]

    # The existing configuration fixture round-trips as well
    seq5 = sequenceFromTOML(joinpath(testConfigDir, "TestDeviceWorkingScanner", "Sequences", "1DSequence.toml"))
    @test sequenceFromDict(MPIMeasurements.toDict(seq5)) == seq5
  end

  @testset "Special channel types" begin
    seq = sequenceFromTOML(sequenceFixture("SpecialChannelsSequence.toml"))
    awg = seq["df"]["chanx"]["awg"]
    @test awg isa ArbitraryElectricalComponent
    @test waveform(awg) == WAVEFORM_ARBITRARY
    @test dfWaveform(seq) == reshape([WAVEFORM_ARBITRARY], 1, 1)
    @test MPIMeasurements.values(awg) == [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]

    rot = seq["mech"]["rot"]
    @test rot isa StepwiseMechanicalRotationChannel
    @test rot.stepAngle ≈ (π / 2)u"rad"
    @test rot.direction == MPIMeasurements.MECHANICAL_ROTATION_DIRECTION_BACKWARD
    @test stepPriority(rot) == 2
    @test preStepPause(rot) == 1.0u"s"
    @test postStepPause(rot) == 0.0u"s" # default
    @test stepsPerCycle(rot) == 4

    spin = seq["mech"]["spin"]
    @test spin isa ContinuousMechanicalRotationChannel
    @test spin.divider == 125000
    @test spin.phase ≈ (π / 2)u"rad"

    sweep = seq["offsets"]["sweep"]
    @test sweep isa ProtocolOffsetElectricalChannel
    @test MPIMeasurements.values(sweep) ≈ [-2.0, -1.0, 0.0, 1.0, 2.0] .* u"mT"
    @test MPIMeasurements.protocolTxChannels(seq["offsets"]) == [sweep]

    # The arbitrary component survives a round trip
    dict = MPIMeasurements.toDict(seq)
    delete!(dict["Fields"], "mech")
    delete!(dict["Fields"], "offsets")
    seq2 = sequenceFromDict(dict)
    @test seq2["df"] == seq["df"]

    dict = MPIMeasurements.toDict(seq)
    delete!(dict["Fields"], "offsets")
    @test dict["Fields"]["mech"]["rot"]["direction"] == "backward"
    @test sequenceFromDict(dict)["mech"]["rot"] == rot
    # The continuous rotation channel on its own round-trips fine
    dict = MPIMeasurements.toDict(seq)
    delete!(dict["Fields"], "offsets")
    delete!(dict["Fields"]["mech"], "rot")
    @test sequenceFromDict(dict)["mech"]["spin"] == spin
    dict = MPIMeasurements.toDict(seq)
    delete!(dict["Fields"], "mech")
    @test dict["Fields"]["offsets"]["sweep"]["type"] == "ProtocolOffsetElectricalChannel"
    @test sequenceFromDict(dict)["offsets"]["sweep"] == sweep
  end
end
