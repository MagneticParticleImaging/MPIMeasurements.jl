@testset "Simple simulated scanner" begin
  scannerName_ = "TestSimpleSimulatedScanner"
  scanner = MPIScanner(scannerName_)

  path = normpath(string(@__DIR__), "TestConfigs/TestSimpleSimulatedScanner/Sequences/Sequence.toml")
  sequence = sequenceFromTOML(path)
  setupSequence(scanner, sequence)

  uMeas, uRef = readData(getDAQ(scanner), 1, 1)
  plot(uRef[:,1,1,1])
  plot!(uMeas[:,1,1,1])
end