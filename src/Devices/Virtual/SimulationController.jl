export SimulationControllerParams, SimulationController, getSimulationControllers,
       getSimulationController, getSimulatedCoilTemperatures

Base.@kwdef struct SimulationControllerParams <: DeviceParams
  "Initial coil temperatures mapped by the tx channel IDs."
  initialCoilTemperatures::Union{Dict{String, typeof(1.0u"°C")}, Nothing} = nothing
end

SimulationControllerParams(dict::Dict) = params_from_dict(SimulationControllerParams, dict)

Base.@kwdef mutable struct SimulationController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulationControllerParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  "Current coil temperatures mapped by the tx channel IDs."
  coilTemperatures::Union{Dict{String, typeof(1.0u"°C")}, Nothing} = nothing
end

function getSimulationControllers(scanner::MPIScanner)
  simulationControllers = getDevices(scanner, SimulationController)
  if length(simulationControllers) > 1
    error("The scanner has more than one simulation controller device. This should never happen.")
  else
    return simulationControllers
  end
end
getSimulationController(scanner::MPIScanner) = getSimulationControllers(scanner)[1]

function init(simCont::SimulationController)
  @debug "Initializing simulation controller with ID `$(simCont.deviceID)`."

  if !isnothing(simCont.params.initialCoilTemperatures)
    simCont.coilTemperatures = simCont.params.initialCoilTemperatures
  end

  simCont.present = true
end

neededDependencies(::SimulationController) = []
optionalDependencies(::SimulationController) = []

Base.close(simCont::SimulationController) = nothing

currentCoilTemperatures(simCont::SimulationController) = simCont.coilTemperatures
currentCoilTemperatures(simCont::SimulationController, channelID::String) = simCont.coilTemperatures[channelID]
currentCoilTemperatures(simCont::SimulationController, channelID::String, value::typeof(1.0u"K")) = simCont.coilTemperatures[channelID] = value

initialCoilTemperatures(simCont::SimulationController) = simCont.params.initialCoilTemperatures
initialCoilTemperatures(simCont::SimulationController, channelID::String) = simCont.params.initialCoilTemperatures[channelID]