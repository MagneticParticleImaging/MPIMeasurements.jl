@testset "Protocols" begin
  include("ProtocolLoadingTests.jl")
  include("MultiSequenceSystemMatrixProtocolTest.jl")
  include("MPSMeasurementProtocolTest.jl")
end
