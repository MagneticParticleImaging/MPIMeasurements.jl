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
using Scratch
using Mmap

# TODO: This is a workaround for CI with GTK since precompilation fails with headless systems
# Remove after https://github.com/JuliaGraphics/Gtk.jl/issues/346 is resolved
if isinteractive()
  using Gtk
end

import Base.write

export addConfigurationPath

scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

include("Devices/Device.jl")
include("Utils/Utils.jl")
include("Scanner.jl")
include("Devices/Devices.jl")
include("Protocols/Protocol.jl")

end # module
