using Test
using Aqua

using MPIMeasurementsTinkerforge

@testset "MPIMeasurementsTinkerforge" begin
  @testset "Aqua" begin
    Aqua.test_all(MPIMeasurementsTinkerforge, ambiguities=false, stale_deps=false) # Stale deps deactivated due to errors with python packages
  end

  # Add tests here
end