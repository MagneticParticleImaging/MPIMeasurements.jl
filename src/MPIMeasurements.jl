module MPIMeasurements

#using MPIFiles: calibration
#using Dates: include
#using Reexport: include
#using Pkg

#using Compat
using Reexport: include
using Reexport
@reexport using MPIFiles
using Unitful
using TOML
#using ThreadPools
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

# TODO: This is a workaround for CI with GTK since precompilation fails with headless systems
# Remove after https://github.com/JuliaGraphics/Gtk.jl/issues/346 is resolved
try
  using Gtk
  @info "This session is interactive and thus we loaded Gtk.jl"
catch e
  if e isa InitError
    @warn "This session is NOT interactive and thus we won't load Gtk.jl. This might lead to errors when calling certain functions."
  end
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
