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

numChannels(sensor::DummyTemperatureSensor) = 50
getTemperatures(sensor::DummyTemperatureSensor) = [(30+i+0.4*randn())*u"°C" for i=1:numChannels(sensor)]
getTemperature(sensor::DummyTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"
getChannelNames(sensor::DummyTemperatureSensor) = ["channel $i" for i=1:numChannels(sensor)]
getChannelGroups(sensor::DummyTemperatureSensor) = floor.(Int,(0:(numChannels(sensor)-1)) ./ numChannels(sensor) * 5 .+ 1)