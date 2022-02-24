export TemperatureSensor, getTemperatureSensors, getTemperatureSensor, numChannels, getTemperatures, getTemperature, getChannelNames

abstract type TemperatureSensor <: Device end

include("DummyTemperatureSensor.jl")
include("ArduinoTemperatureSensor.jl")
#include("FOTemp.jl")

Base.close(t::TemperatureSensor) = nothing

@mustimplement numChannels(sensor::TemperatureSensor)
@mustimplement getTemperatures(sensor::TemperatureSensor)
@mustimplement getTemperature(sensor::TemperatureSensor, channel::Int)

getTemperatureSensors(scanner::MPIScanner) = getDevices(scanner, TemperatureSensor)
getTemperatureSensor(scanner::MPIScanner) = getDevice(scanner, TemperatureSensor)

