export TemperatureSensor, getTemperatureSensors, getTemperatureSensor, numChannels, getTemperatures, getTemperature

abstract type TemperatureSensor <: Device end

include("DummyTemperatureSensor.jl")
include("ArduinoTemperatureSensor.jl")
#include("FOTemp.jl")

Base.close(t::TemperatureSensor) = nothing

@mustimplement numChannels(sensor::TemperatureSensor)
@mustimplement getTemperatures(sensor::TemperatureSensor)
@mustimplement getTemperature(sensor::TemperatureSensor, channel::Int)

getTemperatureSensors(scanner::MPIScanner) = getDevices(scanner, TemperatureSensor)
function getTemperatureSensor(scanner::MPIScanner)
  temperatureSensors = getTemperatureSensors(scanner)
  if length(temperatureSensors) > 1
    error("The scanner has more than one temperature sensor device. Therefore, a single temperature sensor cannot be retrieved unambiguously.")
  else
    return temperatureSensors[1]
  end
end
