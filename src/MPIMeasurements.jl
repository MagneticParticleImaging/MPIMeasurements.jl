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

export deviceID, params, addConfigurationPath

# abstract supertype for all measObj etc.
# Note: This is placed here since e.g. the robot tour needs it, but measurements need AbstractDAQ.
# TODO: A tour is more like a measurement and should not be with the device definitions.
# abstract type MeasObj end

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

deviceID(device::Device) = :deviceID in fieldnames(typeof(device)) ? device.deviceID : error("The device struct for `$(typeof(device))` must have a field `deviceID`.")
params(device::Device) = :params in fieldnames(typeof(device)) ? device.params : error("The device struct for `$(typeof(device))` must have a field `params`.")
dependencies(device::Device) = :dependencies in fieldnames(typeof(device)) ? device.dependencies : error("The device struct for `$(typeof(device))` must have a field `dependencies`.")
function dependencies(device::Device, type::DataType)
  return [dependency for dependency in values(dependencies(device)) if dependency isa type]
end

@mustimplement init(device::Device)
@mustimplement checkDependencies(device::Device)

scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here
addConfigurationPath(path::String) = push!(scannerConfigurationPath, path)

include("Utils/Utils.jl")
include("Scanner/Scanner.jl")
include("Devices/Devices.jl")
#include("Measurements/Measurements.jl") # Deactivate for now in order to not hinder the restructuring

end # module
