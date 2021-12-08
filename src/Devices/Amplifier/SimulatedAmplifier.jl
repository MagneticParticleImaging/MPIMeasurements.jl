export SimulatedAmplifier, SimulatedAmplifierParams

Base.@kwdef struct SimulatedAmplifierParams <: DeviceParams
  mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	voltageMode::AmplifierVoltageMode = AMP_LOW_VOLTAGE_MODE # This should be the safe default
	matchingNetwork::Integer = 1
end
SimulatedAmplifierParams(dict::Dict) = params_from_dict(SimulatedAmplifierParams, dict)

Base.@kwdef mutable struct SimulatedAmplifier <: Amplifier
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedAmplifierParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  state::Bool = false
  mode::AmplifierMode = AMP_VOLTAGE_MODE
  voltageMode::AmplifierVoltageMode = AMP_LOW_VOLTAGE_MODE
  network::Integer = 1
end

function _init(amp::SimulatedAmplifier)
  # Set values given by configuration
	mode(amp, amp.params.mode)
	voltageMode(amp, amp.params.voltageMode)
	matchingNetwork(amp, amp.params.matchingNetwork)
end

checkDependencies(amp::SimulatedAmplifier) = true

Base.close(amp::SimulatedAmplifier) = nothing

state(amp::SimulatedAmplifier) = amp.state
turnOn(amp::SimulatedAmplifier) = amp.state = true
turnOff(amp::SimulatedAmplifier) = amp.state = false
mode(amp::SimulatedAmplifier) = amp.mode
mode(amp::SimulatedAmplifier, mode::AmplifierMode) = amp.mode = mode
voltageMode(amp::SimulatedAmplifier) = amp.voltageMode
voltageMode(amp::SimulatedAmplifier, mode::AmplifierVoltageMode) = amp.voltageMode = mode
matchingNetwork(amp::SimulatedAmplifier) = amp.network
matchingNetwork(amp::SimulatedAmplifier, network::Integer) = amp.network = network
temperature(amp::SimulatedAmplifier) = 25.0u"°C"