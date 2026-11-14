@testset "asyncProducer device cleanup" begin
  scanner_ = MPIScanner("TestProducerCleanupScanner")
  protocol = ScannerProtocol(scanner_)
  sequence = Sequence(joinpath(@__DIR__, "..", "Sequences", "TOML", "SimulatedScannerSequence.toml"))

  su = getSurveillanceUnit(scanner_)
  tempControl = getTemperatureController(scanner_)
  robot = getDevice(scanner_, SimulatedRobot)
  enable(robot)
  workingAmp = getDevice(scanner_, SimulatedAmplifier)
  failingAmp = getDevice(scanner_, TestFailingAmplifier)

  # The failing amplifier is turned on after the AC power, temperature control and
  # robot have been switched to their measurement state.
  @test_throws "failing_amplifier failed to turn on" MPIMeasurements.asyncProducer(Channel{Int}(1), protocol, sequence)
  @test getACStatus(su) == false
  @test tempControl.controlEnabled
  @test state(robot) == MPIMeasurements.READY
  @test state(workingAmp) == false
  @test failingAmp.turnOffCalls == 1

  close(scanner_)
end
