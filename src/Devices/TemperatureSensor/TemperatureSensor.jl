export TemperatureSensor

@quasiabstract struct TemperatureSensor <: Device end

include("DummyTemperatureSensor.jl")
#include("FOTemp.jl")

Base.close(t::TemperatureSensor) = nothing

@mustimplement numChannels(sensor::TemperatureSensor)
@mustimplement getTemperature(sensor::TemperatureSensor)
@mustimplement getTemperature(sensor::TemperatureSensor, channel::Int)
