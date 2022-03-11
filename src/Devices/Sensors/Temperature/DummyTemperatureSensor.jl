export DummyTemperatureSensor, DummyTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct DummyTemperatureSensorParams <: DeviceParams
  
end
DummyTemperatureSensorParams(dict::Dict) = params_from_dict(DummyTemperatureSensorParams, dict)

Base.@kwdef mutable struct DummyTemperatureSensor <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyTemperatureSensorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
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