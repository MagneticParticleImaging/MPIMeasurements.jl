module MPIMeasurements

using Pkg

using Compat
using Reexport
@reexport using MPIFiles
using Unitful
using TOML
using ThreadPools
using HDF5
using ProgressMeter
using Sockets
using DelimitedFiles
using LinearAlgebra
using Statistics
using Dates
using InteractiveUtils
using Graphics: @mustimplement

import Base.write

export deviceID, params, dependencies, init, checkDependencies, addConfigurationPath

# abstract supertype for all measObj etc.
# Note: This is placed here since e.g. the robot tour needs it, but measurements need AbstractDAQ.
# TODO: A tour is more like a measurement and should not be with the device definitions.
# abstract type MeasObj end

scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

include("Devices/Device.jl")
include("Utils/Utils.jl")
include("Scanner.jl")
include("Devices/Devices.jl")
#include("Measurements/Measurements.jl") # Deactivate for now in order to not hinder the restructuring

end # module
