@testset "Channels" begin
  baseFreq = 125.0e6u"Hz"

  @testset "ContinuousElectricalChannel values" begin
    # 16 / 4 = 4 patches, offset 0.5 A, amplitude 1 A
    chan(w; phase = 0.0u"rad") = ContinuousElectricalChannel(id = "c", divider = 16, dividerSteps = 4,
      amplitude = 1.0u"A", offset = 0.5u"A", phase = phase, waveform = w)

    # Sine sampled at 0, 1/4, 1/2, 3/4 of the period
    @test MPIMeasurements.values(chan(WAVEFORM_SINE)) ≈ [0.5, 1.5, 0.5, -0.5] .* u"A"
    # A phase of π/2 turns it into a cosine
    @test MPIMeasurements.values(chan(WAVEFORM_SINE, phase = (π / 2)u"rad")) ≈ [1.5, 0.5, -0.5, 0.5] .* u"A"
    @test MPIMeasurements.values(chan(WAVEFORM_SQUARE)) == [1.5, 1.5, -0.5, -0.5] .* u"A"
    # Sawtooth: linear ramp from offset-amplitude to offset+amplitude (or back)
    @test MPIMeasurements.values(chan(WAVEFORM_SAWTOOTH_RISING)) ≈ [-0.5, 0.5 - 1 / 3, 0.5 + 1 / 3, 1.5] .* u"A"
    @test MPIMeasurements.values(chan(WAVEFORM_SAWTOOTH_FALLING)) ≈ [1.5, 0.5 + 1 / 3, 0.5 - 1 / 3, -0.5] .* u"A"
    # Triangle: 4|x/N - round(x/N)| - 1 for x = 1..N gives 0, 1, 0, -1
    @test MPIMeasurements.values(chan(WAVEFORM_TRIANGLE)) ≈ [0.5, 1.5, 0.5, -0.5] .* u"A"
    # For ramps and triangles the phase shifts the samples by ceil(phase/2π * N)
    @test MPIMeasurements.values(chan(WAVEFORM_TRIANGLE, phase = (π / 2)u"rad")) ≈ [-0.5, 0.5, 1.5, 0.5] .* u"A"
    @test MPIMeasurements.values(chan(WAVEFORM_SAWTOOTH_RISING, phase = (π / 2)u"rad")) ≈ [1.5, -0.5, 0.5 - 1 / 3, 0.5 + 1 / 3] .* u"A"

    @test MPIMeasurements.enableValues(chan(WAVEFORM_SINE)) == [true, true, true, true]
    @test isStepwise(chan(WAVEFORM_SINE))
    @test !isContinuous(chan(WAVEFORM_SINE))
    @test !MPIMeasurements.unitIsTesla(chan(WAVEFORM_SINE))
    @test MPIMeasurements.unitIsTesla(ContinuousElectricalChannel(id = "c", divider = 16, dividerSteps = 4,
      amplitude = 0.001u"T", offset = 0.0u"T", phase = 0.0u"rad"))

    # The cycle of 16 samples at 125 MHz lasts 128 ns, but baseFrequency/divider is
    # returned, which is a frequency
    @test_broken dimension(cycleDuration(chan(WAVEFORM_SINE), baseFreq)) == dimension(u"s")
  end

  @testset "StepwiseElectricalChannel" begin
    chan = StepwiseElectricalChannel(id = "s", divider = 12, values = [0.001, 0.002, 0.003] .* u"T")
    @test MPIMeasurements.values(chan) ≈ [1.0, 2.0, 3.0] .* u"mT"
    @test MPIMeasurements.enableValues(chan) == [true, true, true] # default: all enabled
    @test stepsPerCycle(chan) == 3
    @test cycleDuration(chan, baseFreq) ≈ 12 / 125.0e6 * u"s"
    @test MPIMeasurements.unitIsTesla(chan)
    MPIMeasurements.values!(chan, [1.0, 2.0] .* u"A")
    @test MPIMeasurements.values(chan) == [1.0, 2.0] .* u"A"
    @test !MPIMeasurements.unitIsTesla(chan)
    @test isStepwise(chan)

    chan2 = StepwiseElectricalChannel(id = "s", divider = 12, values = [1.0, 2.0] .* u"V", enable = [false, true])
    @test MPIMeasurements.enableValues(chan2) == [false, true]
  end

  @testset "PeriodicElectricalChannel and components" begin
    c1 = PeriodicElectricalComponent(id = "c1", divider = 4800, amplitude = [0.010u"T", 0.020u"T"], phase = [0.0u"rad", 1.0u"rad"])
    c2 = PeriodicElectricalComponent(id = "c2", divider = 4864, amplitude = [0.001u"T"], phase = [0.0u"rad"], waveform = WAVEFORM_TRIANGLE)
    chan = PeriodicElectricalChannel(id = "p", components = ElectricalComponent[c1, c2])
    @test isContinuous(chan)
    @test !isStepwise(chan)
    @test MPIMeasurements.isDfChannel(chan) # default
    @test offset(chan) == 0.0u"T" # default
    @test uconvert(u"s", cycleDuration(chan, baseFreq)) ≈ lcm(4800, 4864) / 125.0e6 * u"s"

    # Per-period values
    @test amplitude(c1) == 0.010u"T"
    @test amplitude(c1, period = 2) == 0.020u"T"
    @test phase(c1, 2) == 1.0u"rad"
    amplitude!(c1, 0.025u"T", period = 2)
    @test amplitude(c1, period = 2) == 0.025u"T"
    phase!(c1, 2.0u"rad", period = 2)
    @test phase(c1, 2) == 2.0u"rad"
    @test waveform(c2) == WAVEFORM_TRIANGLE
    MPIMeasurements.waveform!(c2, WAVEFORM_SQUARE)
    @test waveform(c2) == WAVEFORM_SQUARE

    @test id.(components(chan)) == ["c1", "c2"]
    pop!(chan)
    @test length(chan) == 1
    push!(chan, c2)
    @test length(chan) == 2
    empty!(chan)
    @test isempty(components(chan))
  end

  @testset "ArbitraryElectricalComponent" begin
    vals = collect(1.0:8.0)
    comp = ArbitraryElectricalComponent(id = "a", divider = 5000, amplitude = [0.002u"T"], phase = [0.0u"rad"], values = vals)
    @test MPIMeasurements.scaledValues(comp) ≈ 0.002u"T" .* vals
    # A phase of π/2 shifts the waveform by a quarter of its 8 samples
    phase!(comp, (π / 2)u"rad")
    @test MPIMeasurements.scaledValues(comp) ≈ 0.002u"T" .* [7.0, 8.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    phase!(comp, (1.0π)u"rad")
    @test MPIMeasurements.scaledValues(comp) ≈ 0.002u"T" .* [5.0, 6.0, 7.0, 8.0, 1.0, 2.0, 3.0, 4.0]

    MPIMeasurements.values!(comp, [0.0, 1.0, 0.0, -1.0])
    phase!(comp, 0.0u"rad")
    amplitude!(comp, 0.003u"T")
    @test MPIMeasurements.scaledValues(comp) ≈ 0.003u"T" .* [0.0, 1.0, 0.0, -1.0]
    @test waveform(comp) == WAVEFORM_ARBITRARY
    @test_throws ErrorException MPIMeasurements.waveform!(comp, WAVEFORM_SINE)

    # Loading from a dict: inline values, jump warning and missing waveform files
    compDict(values) = Dict{String, Any}("type" => "ArbitraryElectricalComponent", "divider" => 5000,
      "amplitude" => ["1.0mT"], "phase" => ["0.0rad"], "values" => values)
    c = MPIMeasurements.createChannelComponent("a", compDict([0.0, 1.0, 0.0]))
    @test c isa ArbitraryElectricalComponent
    @test MPIMeasurements.values(c) == [0.0, 1.0, 0.0]
    @test_logs (:warn, r"jump") MPIMeasurements.createChannelComponent("a", compDict([0.0, 1.0]))
    @test_throws MPIMeasurements.SequenceConfigurationError MPIMeasurements.createChannelComponent("a",
      compDict("MPIMeasurementsTestDoesNotExist_$(time_ns()).h5"))
  end

  @testset "SweepElectricalComponent" begin
    sweep = SweepElectricalComponent(divider = [4800, 9600], amplitude = [0.001u"T", 0.002u"T"])
    @test divider(sweep) == 4800
    @test divider(sweep, 2) == 9600
    @test phase(sweep) == 0.0u"rad"
    @test waveform(sweep) == WAVEFORM_SINE
    # amplitude() refers to an undefined variable `period` instead of `trigger`
    @test_broken (try amplitude(sweep, trigger = 2) == 0.002u"T"; catch; false; end)
  end

  @testset "Mechanical channels" begin
    rotDict(dir) = Dict{String, Any}("type" => "StepwiseMechanicalRotationChannel", "direction" => dir)
    @test MPIMeasurements.createFieldChannel("r", rotDict("forward")).direction == MPIMeasurements.MECHANICAL_ROTATION_DIRECTION_FORWARD
    @test MPIMeasurements.createFieldChannel("r", rotDict("backward")).direction == MPIMeasurements.MECHANICAL_ROTATION_DIRECTION_BACKWARD
    @test_throws ErrorException MPIMeasurements.createFieldChannel("r", rotDict("sideways"))
    # The branch meant for "standstill" compares against "forward" a second time
    @test_broken (try MPIMeasurements.createFieldChannel("r", rotDict("standstill")).direction ==
      MPIMeasurements.MECHANICAL_ROTATION_DIRECTION_STANDSTILL; catch; false; end)

    rot = StepwiseMechanicalRotationChannel(id = "r", stepAngle = 30.0u"°")
    @test rot.direction == MPIMeasurements.MECHANICAL_ROTATION_DIRECTION_STANDSTILL # default
    @test stepPriority(rot) == 99 # default
    @test stepsPerCycle(rot) == 12
    @test isnothing(cycleDuration(rot, baseFreq))
    @test isStepwise(rot)
    @test doesRotationMovement(rot)
    @test !doesTranslationMovement(rot)
    @test mechanicalMovementType(typeof(rot)) isa RotationTxChannel

    trans = StepwiseMechanicalTranslationChannel(id = "t", speed = 0.001u"m/s", positions = [0.0, 1.0, 2.0, 3.0] .* u"mm", stepPriority = 1)
    @test stepsPerCycle(trans) == 4
    @test isnothing(cycleDuration(trans, baseFreq))
    @test doesTranslationMovement(trans)
    @test !doesRotationMovement(trans)

    transDict(speed) = Dict{String, Any}("type" => "StepwiseMechanicalTranslationChannel", "speed" => speed,
      "positions" => ["0.0mm", "10.0mm"], "postStepPause" => "100.0ms")
    t = MPIMeasurements.createFieldChannel("t", transDict("0.002m/s"))
    @test t.positions ≈ [0.0, 10.0] .* u"mm"
    @test postStepPause(t) ≈ 0.1u"s"
    # The speed field is a union of a scalar and a vector type, so Julia cannot convert
    # a speed given in another unit (e.g. "2.0mm/s") to m/s
    @test_broken (try MPIMeasurements.createFieldChannel("t", transDict("2.0mm/s")).speed ≈ 0.002u"m/s"; catch; false; end)

    # Stepwise channels are ordered by their step priority
    @test isless(trans, rot)
    @test !isless(rot, trans)
    @test id.(sort(TxChannel[rot, trans])) == ["t", "r"]
    spin = ContinuousMechanicalRotationChannel(id = "c", divider = 100, phase = 0.0u"rad")
    @test isless(spin, rot)  # continuous before stepwise
    @test !isless(rot, spin)
    @test isContinuous(spin)
    @test doesRotationMovement(spin)

    # The positions are parsed into a vector, but the struct expects a tuple
    contDict = Dict{String, Any}("type" => "ContinuousMechanicalTranslationChannel", "speed" => "1.0mm/s", "positions" => ["0.0mm", "10.0mm"])
    @test_broken (try MPIMeasurements.createFieldChannel("t", contDict) isa ContinuousMechanicalTranslationChannel; catch; false; end)
    contTrans = ContinuousMechanicalTranslationChannel(id = "t", speed = 1.0u"mm/s", positions = (0.0u"mm", 10.0u"mm"))
    @test isContinuous(contTrans)
    @test doesTranslationMovement(contTrans)
    # cycleDuration refers to an undefined variable `speed` instead of `channel.speed`
    @test_broken (try cycleDuration(contTrans, baseFreq) ≈ 10.0u"s"; catch; false; end)
  end

  @testset "ProtocolOffsetElectricalChannel" begin
    chan = ProtocolOffsetElectricalChannel(id = "o", offsetStart = -0.002u"T", offsetStop = 0.002u"T", numOffsets = 5)
    @test MPIMeasurements.values(chan) ≈ [-2.0, -1.0, 0.0, 1.0, 2.0] .* u"mT"
    # Zero counts as positive
    @test MPIMeasurements.values(chan, true) ≈ [0.0, 1.0, 2.0] .* u"mT"
    @test MPIMeasurements.values(chan, false) ≈ [-2.0, -1.0] .* u"mT"
    @test isStepwise(chan)

    offsetDict(start, stop) = Dict{String, Any}("type" => "ProtocolOffsetElectricalChannel",
      "offsetStart" => start, "offsetStop" => stop, "numOffsets" => 3)
    @test MPIMeasurements.createFieldChannel("o", offsetDict("-1.0A", "1.0A")).offsetStop == 1.0u"A"
    @test MPIMeasurements.createFieldChannel("o", offsetDict("0.0V", "1.0V")).offsetStop == 1.0u"V"
    # Integer values with a prefixed unit (e.g. "2mT") are converted to Rational and
    # do not match the Float64 type parameter
    @test_broken (try MPIMeasurements.createFieldChannel("o", offsetDict("-2mT", "2mT")) isa ProtocolOffsetElectricalChannel; catch; false; end)
  end
end
