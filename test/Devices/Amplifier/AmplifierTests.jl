@testset "Amplifiers" begin
  @testset "SimulatedAmplifier" begin
    include("SimulatedAmplifierTest.jl")
  end

  if "hubert" in ARGS
    @testset "HubertAmplifier" begin
      include("HubertAmplifierTest.jl")
    end
  end
end