using Test
using Aqua

using MPIMeasurementsTinkerforge

@testset "MPIMeasurementsTinkerforge" begin
  @testset "Aqua" begin
    Aqua.test_all(MPIMeasurementsTinkerforge, ambiguities=false)
  end

  # Add tests here
end