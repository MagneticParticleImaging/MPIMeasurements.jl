using Test
using Aqua
using Unitful

using MPIMeasurements

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

@testset "MPIMeasurements" begin
  @testset "Aqua" begin
    @warn "Ambiguities and piracies are accepted for now"
    Aqua.test_all(MPIMeasurements, ambiguities=false, piracy=false)
  end

  include("TestDevices.jl")

  include("Scanner/ScannerTests.jl")

  testScanner = "TestSimpleSimulatedScanner"
  include("Devices/DeviceTests.jl")
  #include("Safety/SafetyTests.jl")

  include("Utils/UtilTests.jl")
end