export SimulatedTemperatureSensor, SimulatedTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct SimulatedTemperatureSensorParams <: DeviceParams
  
end
SimulatedTemperatureSensorParams(dict::Dict) = params_from_dict(SimulatedTemperatureSensorParams, dict)

Base.@kwdef mutable struct SimulatedTemperatureSensor <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedTemperatureSensorParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

init(sensor::SimulatedTemperatureSensor) = nothing
checkDependencies(sensor::SimulatedTemperatureSensor) = true

numChannels(sensor::SimulatedTemperatureSensor) = 1
getTemperature(sensor::SimulatedTemperatureSensor)::Vector{typeof(1u"°C")} = [42u"°C"]
getTemperature(sensor::SimulatedTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"