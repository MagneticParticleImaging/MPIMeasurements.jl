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
