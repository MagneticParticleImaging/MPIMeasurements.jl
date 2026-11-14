# Scanner with a simulated DAQ, shared by the storage tests
simulatedScanner = MPIScanner("TestSimpleSimulatedScanner")

@testset "Storage" begin
  include("ChainableBufferTests.jl")
  include("MDFTests.jl")
end
