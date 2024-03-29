export TemperatureSensor
abstract type TemperatureSensor <: Device end

include("ArduinoTemperatureSensor.jl")
include("DummyTemperatureSensor.jl")
#include("FOTemp.jl")
include("SimulatedTemperatureSensor.jl")

Base.close(t::TemperatureSensor) = nothing

export getTemperatureSensors
getTemperatureSensors(scanner::MPIScanner) = getDevices(scanner, TemperatureSensor)

export getTemperatureSensor
getTemperatureSensor(scanner::MPIScanner) = getDevice(scanner, TemperatureSensor)

export numChannels
@mustimplement numChannels(sensor::TemperatureSensor)

export getTemperatures
@mustimplement getTemperatures(sensor::TemperatureSensor)

export getTemperature
@mustimplement getTemperature(sensor::TemperatureSensor, channel::Int)

export getChannelNames
@mustimplement getChannelNames(sensor::TemperatureSensor)

export getChannelGroups
@mustimplement getChannelGroups(sensor::TemperatureSensor)
