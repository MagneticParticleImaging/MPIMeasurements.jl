export SimulatedDisplayParams, SimulatedDisplay

Base.@kwdef struct SimulatedDisplayParams <: DeviceParams
  
end
SimulatedDisplayParams(dict::Dict) = params_from_dict(SimulatedDisplayParams, dict)

Base.@kwdef mutable struct SimulatedDisplay <: Display
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedDisplayParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  displayRepresention::Matrix{Char} = fill(' ', (4, 20))
  backlightState::Bool = false
  showChanges::Bool = false
end

function init(disp::SimulatedDisplay)
  @debug "Initializing simulated display unit with ID `$(disp.deviceID)`."

  disp.present = true
end

checkDependencies(disp::SimulatedDisplay) = true

Base.close(disp::SimulatedDisplay) = nothing

clear(disp::SimulatedDisplay) = disp.displayRepresention = fill(' ', (4, 20))
function writeLine(disp::SimulatedDisplay, row::Integer, column::Integer, message::String)
  disp.displayRepresention[row, column:column+length(message)-1] = collect(message)

  if disp.showChanges
    map(println, mapslices(String, test, dims=2))
  end
end
hasBacklight(disp::SimulatedDisplay) = true
setBacklight(disp::SimulatedDisplay, state::Bool) = backlightState = state