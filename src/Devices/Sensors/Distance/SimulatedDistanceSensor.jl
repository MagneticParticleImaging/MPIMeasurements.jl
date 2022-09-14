export SimulatedDistanceSensor, SimulatedDistanceSensorParams

Base.@kwdef struct SimulatedDistanceSensorParams <: DeviceParams
  
end
SimulatedDistanceSensorParams(dict::Dict) = params_from_dict(SimulatedDistanceSensorParams, dict)

Base.@kwdef mutable struct SimulatedDistanceSensor <: DistanceSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedDistanceSensorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

init(sensor::SimulatedDistanceSensor) = sensor.present = true
neededDependencies(::SimulatedDistanceSensor) = []
optionalDependencies(::SimulatedDistanceSensor) = []
Base.close(sensor::SimulatedDistanceSensor) = nothing

getDistance(sensor::SimulatedDistanceSensor) = 42u"mm"