export SimulatedTemperatureSensor, SimulatedTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct SimulatedTemperatureSensorParams <: DeviceParams
  
end
SimulatedTemperatureSensorParams(dict::Dict) = params_from_dict(SimulatedTemperatureSensorParams, dict)

Base.@kwdef mutable struct SimulatedTemperatureSensor <: TemperatureSensor
  @add_device_fields SimulatedTemperatureSensorParams
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