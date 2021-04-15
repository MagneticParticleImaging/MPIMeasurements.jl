module MPIMeasurements

using Pkg

using Compat
using Reexport
#using IniFile
@reexport using MPIFiles
#@reexport using Redpitaya
@reexport using Unitful
@reexport using Unitful.DefaultSymbols
@reexport using Pkg.TOML
@reexport using ThreadPools
using HDF5
using ProgressMeter
using Sockets
using DelimitedFiles
using LinearAlgebra
using Statistics
using Dates
using InteractiveUtils
using Configurations
using ReusePatterns
#using Winston, Gtk, Gtk.ShortNames

#using MPISimulations

import Base.write
#import PyPlot.disconnect

export deviceID, params, addConfigurationPath

# abstract supertype for all measObj etc.
# Note: This is placed here since e.g. the robot tour needs it, but measurements need AbstractDAQ.
# TODO: A tour is more like a measurement and should not be with the device definitions.
abstract type MeasObj end

"""
Abstract type for all device parameters

Every device must implement a parameter struct using @option in order
to allow for automatic instantiation from the configuration file.
"""
abstract type DeviceParams end

# """
# (Quasi)Abstract supertype for all devices
#
# Every device has to implement its own device struct which identifies it.
#
# """
@quasiabstract struct Device
  deviceID::String
  params::DeviceParams
end

deviceID(device::Device) = device.deviceID
params(device::Device) = device.params

scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

include("Scanner/Scanner.jl")
include("Devices/Devices.jl")
#include("Measurements/Measurements.jl") # Deactivate for now in order to not hinder the restructuring

end # module
