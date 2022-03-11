export SimulatedTemperatureSensor, SimulatedTemperatureSensorParams

Base.@kwdef struct SimulatedTemperatureSensorParams <: DeviceParams
  
end
SimulatedTemperatureSensorParams(dict::Dict) = params_from_dict(SimulatedTemperatureSensorParams, dict)

Base.@kwdef mutable struct SimulatedTemperatureSensor <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedTemperatureSensorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function init(sensor::SimulatedTemperatureSensor)
  # NOP
end
neededDependencies(::SimulatedTemperatureSensor) = []
optionalDependencies(::SimulatedTemperatureSensor) = []
Base.close(sensor::SimulatedTemperatureSensor) = nothing

numChannels(sensor::SimulatedTemperatureSensor) = 1
getTemperature(sensor::SimulatedTemperatureSensor)::Vector{typeof(1u"°C")} = [42u"°C"]
getTemperature(sensor::SimulatedTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"