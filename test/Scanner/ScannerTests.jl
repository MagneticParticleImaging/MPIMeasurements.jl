# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

include("DummyScannerTest.jl")
include("FlexibleScannerTest.jl")
include("SimpleSimulatedScannerTest.jl")
