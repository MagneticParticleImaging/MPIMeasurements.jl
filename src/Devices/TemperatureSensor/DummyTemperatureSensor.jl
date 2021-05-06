export DummyTemperatureSensor, DummyTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct DummyTemperatureSensorParams <: DeviceParams
  
end

Base.@kwdef mutable struct DummyTemperatureSensor <: TemperatureSensor
  deviceID::String
  params::DummyTemperatureSensorParams
end

numChannels(sensor::DummyTemperatureSensor) = 1
getTemperature(sensor::DummyTemperatureSensor)::Vector{typeof(1u"°C")} = [42u"°C"]
getTemperature(sensor::DummyTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"