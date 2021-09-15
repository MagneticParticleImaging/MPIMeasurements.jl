using MPIMeasurements
using Test
using Unitful

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

include("Devices/DeviceTests.jl")
include("Scanner/ScannerTests.jl")