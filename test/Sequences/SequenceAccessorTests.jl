@testset "Accessors" begin
  loadSeq() = sequenceFromTOML(sequenceFixture("MultiChannelSequence.toml"))

  @testset "Drive field" begin
    seq = loadSeq()
    # chanz is periodic but not a drive-field channel
    @test dfNumChannels(seq) == 2
    @test id.(MPIMeasurements.dfChannels(seq)) == ["chanx", "chany"]
    @test dfBaseFrequency(seq) == 125.0u"MHz"
    @test txBaseFrequency(seq) == 125.0u"MHz"

    # Missing components are filled with a divider of 1
    @test dfDivider(seq) == [4800//1 4864//1; 4864//1 1//1]
    @test dfSamplesPerCycle(seq) == lcm(4800, 4864) == 364800
    @test dfCycle(seq) ≈ 2.9184u"ms"
    @test txCycle(seq) == dfCycle(seq)

    # (period, channel, component)
    strength = dfStrength(seq)
    @test size(strength) == (1, 2, 2)
    @test strength[1, 1, 1] == 0.010u"T"
    @test strength[1, 1, 2] ≈ 0.005u"T"
    @test strength[1, 2, 1] ≈ 0.012u"T"
    @test strength[1, 2, 2] == 0.0u"T"

    phases = dfPhase(seq)
    @test size(phases) == (1, 2, 2)
    @test phases[1, 1, 1] == 0.0u"rad"
    @test phases[1, 1, 2] ≈ (π / 2)u"rad"
    @test phases[1, 2, 1] ≈ (1.0π)u"rad"
    @test phases[1, 2, 2] == 0.0u"rad"

    @test dfWaveform(seq) == [WAVEFORM_SINE WAVEFORM_TRIANGLE; WAVEFORM_SINE WAVEFORM_SINE]
  end

  @testset "Receiver and acquisition" begin
    seq = loadSeq()
    @test rxBandwidth(seq) == 7.8125u"MHz"
    @test rxSamplingRate(seq) == 15.625u"MHz"
    # 15.625 MHz * 2.9184 ms
    @test rxNumSamplingPoints(seq) == 45600
    @test rxNumSamplesPerPeriod(seq) == 45600
    @test rxNumChannels(seq) == 2
    @test all(c -> c isa RxChannel, rxChannels(seq))

    # The acyclic channels span 4 drive-field cycles with one step per cycle, the
    # numPeriodsPerFrame entry of the acquisition is ignored in that case
    @test acqNumPeriodsPerFrame(seq) == 4
    @test acqNumPeriodsPerPatch(seq) == 1
    @test acqNumPatches(seq) == 4
    @test isnothing(acqOffsetField(seq))
    @test isnothing(acqGradient(seq))

    @test acqNumFrames(seq) == 10
    @test acqNumAverages(seq) == 3
    @test acqNumFrameAverages(seq) == 2
    acqNumFrames(seq, 42)
    acqNumAverages(seq, 7)
    acqNumFrameAverages(seq, 5)
    @test acqNumFrames(seq) == 42
    @test acqNumAverages(seq) == 7
    @test acqNumFrameAverages(seq) == 5

    # Without acyclic channels the value from the acquisition section is used
    dict = loadFixtureDict("MultiChannelSequence.toml")
    delete!(dict["Fields"], "ff")
    seq2 = sequenceFromDict(dict)
    @test acqNumPeriodsPerFrame(seq2) == 7
    @test acqNumPeriodsPerPatch(seq2) == 1
    @test acqNumPatches(seq2) == 7

    # Optional acquisition entries default to 1
    dict = loadFixtureDict("SpecialChannelsSequence.toml")
    seq3 = sequenceFromDict(dict)
    @test acqNumFrames(seq3) == 1
    @test acqNumAverages(seq3) == 1
    @test acqNumFrameAverages(seq3) == 1
    @test acqNumPeriodsPerFrame(seq3) == 1
  end

  @testset "Channel selection" begin
    seq = loadSeq()
    @test hasElectricalTxChannels(seq)
    @test hasMechanicalTxChannels(seq)
    @test hasPeriodicElectricalTxChannels(seq)
    @test hasAcyclicElectricalTxChannels(seq)
    @test sort(id.(MPIMeasurements.electricalTxChannels(seq))) == ["chanx", "chany", "chanz", "ffx", "ffy"]
    @test id.(MPIMeasurements.periodicElectricalTxChannels(seq)) == ["chanx", "chany", "chanz"]
    @test sort(id.(MPIMeasurements.acyclicElectricalTxChannels(seq))) == ["ffx", "ffy"]
    @test id.(MPIMeasurements.mechanicalTxChannels(seq)) == ["rob"]

    # Periodic channels count as continuous, both acyclic channel types as stepwise
    @test sort(id.(continuousElectricalTxChannels(seq))) == ["chanx", "chany", "chanz"]
    @test sort(id.(stepwiseElectricalTxChannels(seq))) == ["ffx", "ffy"]
    @test hasContinuousElectricalChannels(seq)
    @test hasStepwiseElectricalChannels(seq)
    @test id.(stepwiseMechanicalTxChannels(seq)) == ["rob"]
    @test isempty(continuousMechanicalTxChannels(seq))
    @test hasStepwiseMechanicalChannels(seq)
    @test !hasContinuousMechanicalTxChannels(seq)

    @test needsControl(seq)
    @test !needsDecoupling(seq)
    @test needsControlOrDecoupling(seq)

    df = seq["df"]
    @test length(MPIMeasurements.channels(df, PeriodicElectricalChannel)) == 3
    @test isempty(MPIMeasurements.channels(df, MechanicalTxChannel))
    @test isempty(MPIMeasurements.protocolTxChannels(df))
  end

  @testset "Setters" begin
    seq = loadSeq()
    chanx = seq["df"]["chanx"]

    amplitude!(chanx, "c1", 0.02u"T")
    @test amplitude(chanx["c1"]) == 0.02u"T"
    @test dfStrength(seq)[1, 1, 1] == 0.02u"T"

    phase!(chanx, "c1", 0.25u"rad")
    @test phase(chanx["c1"]) == 0.25u"rad"
    @test dfPhase(seq)[1, 1, 1] == 0.25u"rad"

    divider!(chanx, "c1", 2400)
    @test divider(chanx["c1"]) == 2400
    @test dfDivider(seq)[1, 1] == 2400
    @test dfSamplesPerCycle(seq) == lcm(2400, 4864)

    MPIMeasurements.waveform!(chanx, "c1", WAVEFORM_SQUARE)
    @test waveform(chanx["c1"]) == WAVEFORM_SQUARE
    @test dfWaveform(seq)[1, 1] == WAVEFORM_SQUARE

    offset!(chanx, 0.002u"T")
    @test offset(chanx) ≈ 2.0u"mT"

    # A single-period amplitude may switch its unit
    @test MPIMeasurements.unitIsTesla(chanx)
    amplitude!(chanx["c2"], 0.5u"V")
    @test amplitude(chanx["c2"]) == 0.5u"V"
    @test !MPIMeasurements.unitIsTesla(chanx)
    @test MPIMeasurements.unitIsTesla(seq["df"]["chany"])
    @test !MPIMeasurements.unitIsTesla(seq["df"]["chanz"]) # defined in ampere

    @test_throws "has no component with id nope" amplitude!(chanx, "nope", 0.1u"T")
    @test_throws "has no component with id nope" phase!(chanx, "nope", 0.1u"rad")
    @test_throws "has no component with id nope" divider!(chanx, "nope", 10)
    @test_throws "has no component with id nope" MPIMeasurements.waveform!(chanx, "nope", WAVEFORM_SINE)
    @test_throws ArgumentError amplitude!(chanx, "nope", 0.1u"T")
  end

  @testset "Indexing and iteration" begin
    seq = loadSeq()
    df = seq["df"]
    @test seq[findfirst(==("df"), keys(seq))] === df
    @test haskey(seq, "ff")
    @test !haskey(seq, "nope")
    @test_throws KeyError seq["nope"]
    @test_throws BoundsError seq[0]
    @test_throws BoundsError seq[length(seq) + 1]
    @test seq[end] === fields(seq)[end]
    @test length(collect(seq)) == 3

    # Replace a field by ID, add a new one, remove it again
    newField = MagneticField(id = "df", channels = TxChannel[df["chany"]])
    seq["df"] = newField
    @test length(seq) == 3
    @test length(seq["df"]) == 1
    extra = MagneticField(id = "extra", channels = TxChannel[], control = false, decouple = false)
    seq["extra"] = extra
    @test length(seq) == 4
    @test seq["extra"].safeStartInterval == 0.5u"s"
    @test pop!(seq) === extra
    delete!(seq, "robot")
    @test sort(collect(keys(seq))) == ["df", "ff"]
    @test_throws KeyError delete!(seq, "robot")

    # Fields index their channels
    field = loadSeq()["df"]
    @test field[1] === field["chanx"]
    @test field[end] === field["chanz"]
    @test haskey(field, "chany")
    @test_throws KeyError field["nope"]
    @test_throws BoundsError field[4]
    chanw = PeriodicElectricalChannel(id = "chanw", components = ElectricalComponent[])
    field["chanw"] = chanw # unknown ID -> appended
    @test length(field) == 4
    field["chanw"] = chanw # known ID -> replaced
    @test length(field) == 4
    delete!(field, "chanw")
    @test collect(keys(field)) == ["chanx", "chany", "chanz"]
    @test_throws KeyError delete!(field, "chanw")

    # Periodic channels index their components
    chanx = loadSeq()["df"]["chanx"]
    @test chanx[1] === chanx["c1"]
    @test chanx[end] === chanx["c2"]
    @test haskey(chanx, "c2")
    @test_throws KeyError chanx["nope"]
    @test_throws BoundsError chanx[3]
    @test length(MPIMeasurements.periodicElectricalComponents(chanx)) == 2
    @test isempty(MPIMeasurements.arbitraryElectricalComponents(chanx))
    c3 = PeriodicElectricalComponent(id = "c3", divider = 4800, amplitude = [0.001u"T"], phase = [0.0u"rad"])
    chanx["c3"] = c3 # unknown ID -> appended
    @test length(chanx) == 3
    @test chanx["c3"] === c3
    chanx["c3"] = c3 # known ID -> replaced
    @test length(chanx) == 3
    @test chanx["c3"] === c3
    delete!(chanx, "c3")
    @test collect(keys(chanx)) == ["c1", "c2"]
    @test_throws KeyError delete!(chanx, "c3")

    # The acquisition indexes its receive channels
    acq = loadSeq().acquisition
    @test acq[1] == acq["rx1"]
    @test id(acq[end]) == "rx2"
    @test haskey(acq, "rx2")
    @test_throws KeyError acq["nope"]
    @test_throws BoundsError acq[3]
    push!(acq, RxChannel("rx3"))
    @test collect(keys(acq)) == ["rx1", "rx2", "rx3"]
    delete!(acq, "rx1")
    @test collect(keys(acq)) == ["rx2", "rx3"]
    @test_throws KeyError delete!(acq, "rx1")
    @test MPIMeasurements.toDictValue(RxChannel("rx9")) == "rx9"
  end
end
