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

Every device must implement a parameter struct allowing for
automatic instantiation from the configuration file.
"""
abstract type DeviceParams end

"""
Abstract type for all devices

Every device has to implement its own device struct which identifies it.
A concrete implementation should contain e.g. the handle to device ressources
or internal variables.
The device struct must at least have the fields `deviceID` and `params` and
all other fields should have default values.
"""
abstract type Device end

deviceID(device::Device) = :deviceID in fieldnames(typeof(device)) ? device.deviceID : error("The device struct must have a field `deviceID`.")
params(device::Device) = :params in fieldnames(typeof(device)) ? device.params : error("The device struct must have a field `params`.")

scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

include("Utils/Utils.jl")
include("Scanner/Scanner.jl")
include("Devices/Devices.jl")
#include("Measurements/Measurements.jl") # Deactivate for now in order to not hinder the restructuring

end # module
