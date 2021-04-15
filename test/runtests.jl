using MPIMeasurements
using Test
using Unitful

include("config.jl")

imgdir = joinpath(@__DIR__(), "images")
mkpath(imgdir)


scanner = MPIScanner(conf)

include("Safety/tests.jl")
include("Robots/tests.jl")
include("DAQ/tests.jl")
