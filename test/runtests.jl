using MPIMeasurements
using Test
using Unitful

if isempty(ARGS) || "all" in ARGS
  all_tests = true
else
  all_tests = false
end

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
