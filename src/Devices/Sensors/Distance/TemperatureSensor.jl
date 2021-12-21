export DistanceSensor

abstract type DistanceSensor <: Device end

include("SimulatedDistanceSensor.jl")

Base.close(t::DistanceSensor) = nothing

@mustimplement distance(sensor::DistanceSensor)

getDistanceSensors(scanner::MPIScanner) = getDevices(scanner, DistanceSensor)
getDistanceSensor(scanner::MPIScanner) = getDevice(scanner, DistanceSensor)

