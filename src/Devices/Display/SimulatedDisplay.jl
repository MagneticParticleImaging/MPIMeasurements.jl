export SimulatedDisplayParams, SimulatedDisplay

Base.@kwdef struct SimulatedDisplayParams <: DeviceParams
  
end
SimulatedDisplayParams(dict::Dict) = params_from_dict(SimulatedDisplayParams, dict)

Base.@kwdef mutable struct SimulatedDisplay <: Display
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedGaussMeterParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function init(disp::SimulatedDisplay)
  @debug "Initializing simulated display unit with ID `$(disp.deviceID)`."

  motor.present = true
end

checkDependencies(disp::SimulatedDisplay) = true

Base.close(disp::SimulatedDisplay) = nothing

