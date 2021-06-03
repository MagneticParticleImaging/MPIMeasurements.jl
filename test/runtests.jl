using MPIMeasurements
using Test
using Unitful

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

include("Devices/DeviceTests.jl")
include("Scanner/ScannerTests.jl")


# include("config.jl")
#
# imgdir = joinpath(@__DIR__(), "images")
# mkpath(imgdir)
#
#
# scanner = MPIScanner(conf)
#
# include("Safety/tests.jl")
# include("Robots/tests.jl")
# include("DAQ/tests.jl")
