export DistanceSensor

abstract type DistanceSensor <: Device end

include("SimulatedDistanceSensor.jl")
include("TinkerforgeBrickletDistanceIRV2DistanceSensor.jl")

Base.close(t::DistanceSensor) = nothing

export getDistance
@mustimplement getDistance(sensor::DistanceSensor)

export getDistanceSensors
getDistanceSensors(scanner::MPIScanner) = getDevices(scanner, DistanceSensor)

export getDistanceSensor
getDistanceSensor(scanner::MPIScanner) = getDevice(scanner, DistanceSensor)

