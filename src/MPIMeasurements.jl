module MPIMeasurements

#using MPIFiles: calibration
#using Dates: include
#using Reexport: include
#using Pkg

#using Compat
using UUIDs
using Mmap: settings
using Base: Integer
using Reexport
@reexport using MPIFiles
import MPIFiles: hasKeyAndValue
using Unitful
using TOML
using ThreadPools
#using HDF5
#using ProgressMeter
#using Sockets
#using DelimitedFiles
#using LinearAlgebra
#using Statistics
using Dates
using InteractiveUtils
using Graphics: @mustimplement
using Scratch
using Mmap

import Base.write

export addConfigurationPath

const scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

# circular reference between Scanner.jl and Protocol.jl. Thus we predefine the protocol
abstract type Protocol end

include("Devices/Device.jl")
include("Scanner.jl")
include("Utils/Utils.jl")
include("Devices/Devices.jl")
include("Protocols/Protocol.jl")

function __init__()
  defaultScannerConfigurationPath = joinpath(homedir(),".mpi")
  if isdir(defaultScannerConfigurationPath)
    addConfigurationPath(defaultScannerConfigurationPath)
  end
end

end # module
