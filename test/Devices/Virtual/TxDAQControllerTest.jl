@testset "TxDAQController construction" begin
  txParams = TxDAQControllerParams(phaseAccuracy=0.01u"rad", relativeAmplitudeAccuracy=0.01)
  txCont = TxDAQController(deviceID="txCont", params=txParams, dependencies=Dict{String, Union{Device, Missing}}())
  @test isempty(txCont.controlResults)
  @test isnothing(MPIMeasurements.resetCachedCalibration(txCont))
  @test isempty(txCont.controlResults)
end

@testset "TxDAQController amplifiers" begin
  scanner = MPIScanner("TestSimpleSimulatedScanner")
  daq = getDAQ(scanner)
  seq = sequenceFromTOML(joinpath(testConfigDir, "TestSimpleSimulatedScanner", "Sequences", "SimpleSimulatedSequence.toml"))
  txParams = TxDAQControllerParams(phaseAccuracy=0.01u"rad", relativeAmplitudeAccuracy=0.01)
  noDeps() = Dict{String, Union{Device, Missing}}()

  @testset "without amplifiers" begin
    txCont = TxDAQController(deviceID="txCont", params=txParams, dependencies=Dict{String, Union{Device, Missing}}("daq" => daq))
    amps = MPIMeasurements.getRequiredAmplifiers(txCont, seq)
    @test amps isa Vector{<:Amplifier}
    @test isempty(amps)
    @test isnothing(turnOn(amps))
  end

  @testset "cleanup when an amplifier fails to turn on" begin
    su = DummySurveillanceUnit(deviceID="su", params=DummySurveillanceUnitParams(), dependencies=noDeps())
    amp = TestFailingAmplifier(deviceID="failingAmp", params=TestFailingAmplifierParams(channelID="tx_main"), dependencies=noDeps())
    unusedAmp = SimulatedAmplifier(deviceID="unusedAmp", params=SimulatedAmplifierParams(channelID="other"), dependencies=noDeps())
    deps = Dict{String, Union{Device, Missing}}("daq" => daq, "su" => su, "amp" => amp, "unusedAmp" => unusedAmp)
    txCont = TxDAQController(deviceID="txCont", params=txParams, dependencies=deps)

    @test MPIMeasurements.getRequiredAmplifiers(txCont, seq) == [amp]
    @test_throws "failed to turn on" controlTx(txCont, StubControlSequence(seq))
    @test amp.turnOffCalls == 1
    @test !su.acPowerEnabled
  end
end

@testset "DC search step" begin
  step = MPIMeasurements.dcSearchStep
  voltsPerTesla = [100.0, 50.0]
  minStep = 5e-6
  # Linear system B = 0.01 T/V * V + 1 mT: the secant step reaches the target exactly
  B(V) = 0.01 .* V .+ 1e-3
  previous = (V=[0.1, 0.2], B=B([0.1, 0.2]))
  last = (V=[0.3, 0.5], B=B([0.3, 0.5]))
  for target in ([2e-3, 3e-3], [-2e-3, 0.0], [0.0, 0.0])
    @test step(previous, last, target, voltsPerTesla, minStep) ≈ (target .- 1e-3) ./ 0.01
  end

  # Fields of the last two steps too close together: restart from the forward calibration,
  # also for negative and zero targets
  close_ = (V=[0.3, 0.2000001], B=[B(0.3), B(0.2000001)])
  for target in ([2e-3, 3e-3], [-2e-3, -3e-3], [0.0, 0.0])
    @test step(previous, close_, target, voltsPerTesla, minStep) == target .* voltsPerTesla
  end

  @test_throws "non-finite voltages" step(previous, (V=[0.3, 0.5], B=[NaN, 1.0]), [0.0, 0.0], voltsPerTesla, minStep)
end

@testset "AW Tx time signal and slew rate" begin
  seq = sequenceFromTOML(joinpath(testConfigDir, "TestSimpleSimulatedScanner", "Sequences", "SimpleSimulatedSequence.toml"))
  N = rxNumSamplingPoints(seq)
  samplingRate = rxSamplingRate(seq)
  # 1 V cosine at bin 10; its maximum slew rate is 2π*f*1 V
  tx = zeros(ComplexF64, 1, N÷2+1)
  tx[1, 11] = 1.0
  expectedSlew = 2π*(10*samplingRate/N)*1.0u"V"
  for maxIndex in (N÷2+1, 51)
    # Only the fields used by `txToTimeDomain`
    cont = (maxIndex = maxIndex, currSequence = seq)
    signal, rate = MPIMeasurements.txToTimeDomain(tx, cont)
    Nsignal = maxIndex == N÷2+1 ? N : 2maxIndex-2
    @test size(signal) == (1, Nsignal)
    @test maximum(abs, signal) ≈ 1.0
    @test rate ≈ samplingRate*Nsignal/N
    slew = maximum(abs, diff(signal, dims=2))*u"V"*rate
    @test isapprox(slew, expectedSlew, rtol=0.03)
  end
end

@testset "AW field accuracy" begin
  seq = sequenceFromTOML(joinpath(testConfigDir, "TestSimpleSimulatedScanner", "Sequences", "SimpleSimulatedSequence.toml"))
  nFreq = rxNumSamplingPoints(seq)÷2+1
  # Only `currSequence` and `maxIndex` are used to synthesize the time signals
  cont = MPIMeasurements.AWControlSequence(seq, seq, MPIMeasurements.OrderedDict{PeriodicElectricalChannel, MPIMeasurements.TxChannelParams}(),
    Int[], MPIMeasurements.TransferFunction[], falses(2, 1, nFreq), [], nFreq, zeros(ComplexF64, 0, 0))
  txCont(absolute, dc=nothing) = TxDAQController(deviceID="txCont", dependencies=Dict{String, Union{Device, Missing}}(),
    params=TxDAQControllerParams(phaseAccuracy=0.01u"rad", relativeAmplitudeAccuracy=0.01, absoluteAmplitudeAccuracy=absolute,
      controlDC=!isnothing(dc), dcAccuracy=something(dc, 50.0u"µT")))
  # rfft coefficients: column 1 is the DC field, column k+1 the amplitude of a cosine at bin k
  Ω = zeros(ComplexF64, 2, nFreq)
  Ω[:, 2] = [10e-3, 5e-3]

  # Cosine deviations of 100 µT and 10 µT have mean absolute deviations of 63.7 µT and 6.4 µT:
  # their mean over both channels (35 µT) is below 50 µT, the first channel is not
  Γ = copy(Ω)
  Γ[:, 4] = [100e-6, 10e-6]
  @test !MPIMeasurements.fieldAccuracyReached(cont, txCont(50.0u"µT"), Γ, Ω)
  @test MPIMeasurements.fieldAccuracyReached(cont, txCont(70.0u"µT"), Γ, Ω)

  # DC deviations of 20 µT and -30 µT are only checked if DC is controlled
  Γdc = copy(Ω)
  Γdc[:, 1] = [20e-6, -30e-6]
  @test MPIMeasurements.fieldAccuracyReached(cont, txCont(50.0u"µT"), Γdc, Ω)
  @test MPIMeasurements.fieldAccuracyReached(cont, txCont(50.0u"µT", 40.0u"µT"), Γdc, Ω)
  @test !MPIMeasurements.fieldAccuracyReached(cont, txCont(50.0u"µT", 25.0u"µT"), Γdc, Ω)
end
