using Test
using Aqua
using Unitful
using Pkg
using Statistics

using MPIMeasurements

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

@testset "MPIMeasurements" begin
  @testset "Aqua" begin
    Aqua.test_all(MPIMeasurements)
  end

  include("TestDevices.jl")
  include("Scanner/ScannerTests.jl")
  include("Devices/DeviceTests.jl")
  #include("Safety/SafetyTests.jl")
  include("Utils/UtilTests.jl")

  @testset "Subpackages" begin
    packageNames = ["MPIMeasurementsTinkerforge"]
    for packageName ∈ packageNames
      basePath = joinpath("..", "subpackages", packageName)
      Pkg.activate(basePath)
      Pkg.instantiate()
      include(joinpath(basePath, "test", "runtests.jl"))
    end
  end
end
