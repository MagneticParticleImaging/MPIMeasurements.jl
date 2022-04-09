export DummyTemperatureSensor, DummyTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct DummyTemperatureSensorParams <: DeviceParams
  
end
DummyTemperatureSensorParams(dict::Dict) = params_from_dict(DummyTemperatureSensorParams, dict)

Base.@kwdef mutable struct DummyTemperatureSensor <: TemperatureSensor
  @add_device_fields DummyTemperatureSensorParams
end

function _init(sensor::DummyTemperatureSensor)
  # NOP
end

neededDependencies(::DummyTemperatureSensor) = []
optionalDependencies(::DummyTemperatureSensor) = []

Base.close(sensor::DummyTemperatureSensor) = nothing

numChannels(sensor::DummyTemperatureSensor) = 1
getTemperatures(sensor::DummyTemperatureSensor) = [42u"°C"]
getTemperature(sensor::DummyTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"