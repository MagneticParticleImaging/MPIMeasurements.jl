export SimulatedDCSource, SimulatedDCSourceParams

Base.@kwdef struct SimulatedDCSourceParams <: DeviceParams
  
end
SimulatedDCSourceParams(dict::Dict) = params_from_dict(SimulatedDCSourceParams, dict)

Base.@kwdef mutable struct SimulatedDCSource <: DCSource
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedDCSourceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

init(sensor::SimulatedDCSource) = sensor.present = true
neededDependencies(::SimulatedDCSource) = []
optionalDependencies(::SimulatedDCSource) = []
Base.close(sensor::SimulatedDCSource) = nothing

