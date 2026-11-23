@testset "MPSMeasurementProtocol patch offsets" begin
  scanner_ = MPIScanner("TestSimpleSimulatedScanner")
  protocol = MPSMeasurementProtocol(name = "MPSPatchOffsetsTest", description = "", scanner = scanner_,
    params = MPSMeasurementProtocolParams())
  # Three offsets with two periods each; the first period of each offset is a wait period
  protocol.offsetfields = reshape([0.0, 1.0, 2.0], 3, 1)

  protocol.patchPermutation = [nothing, 1, nothing, 2, nothing, 3]
  @test MPIMeasurements.offsetsPerPatch(protocol) == reshape([0.0, 1.0, 2.0], 3, 1)

  # Patches stored in a different order than measured
  protocol.patchPermutation = [nothing, 3, nothing, 1, nothing, 2]
  @test MPIMeasurements.offsetsPerPatch(protocol) == reshape([1.0, 2.0, 0.0], 3, 1)

  # Without averaging every measured period is stored
  protocol.patchPermutation = [1, 2, 3, 4, 5, 6]
  @test MPIMeasurements.offsetsPerPatch(protocol) == reshape([0.0, 0.0, 1.0, 1.0, 2.0, 2.0], 6, 1)

  # Averaged periods are stored in the same patch
  protocol.patchPermutation = [1, 1, 2, 2, 3, 3]
  @test MPIMeasurements.offsetsPerPatch(protocol) == reshape([0.0, 1.0, 2.0], 3, 1)

  # One column per offset channel
  protocol.offsetfields = [0.0 5.0; 1.0 6.0; 2.0 7.0]
  @test MPIMeasurements.offsetsPerPatch(protocol) == [0.0 5.0; 1.0 6.0; 2.0 7.0]
end
