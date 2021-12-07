using MPIMeasurements
using Test
using Unitful

include("TestDevices.jl")

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

include("Scanner/ScannerTests.jl")

#testScanner = "TestSimpleSimulatedScanner"
#include("Devices/DeviceTests.jl")
#include("Scanner/ScannerTests.jl")
#include("Safety/SafetyTests.jl")