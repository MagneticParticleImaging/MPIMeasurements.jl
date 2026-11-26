export SimulatedAmplifier, SimulatedAmplifierParams

Base.@kwdef struct SimulatedAmplifierParams <: DeviceParams
  channelID::String
  mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	powerSupplyMode::AmplifierPowerSupplyMode = AMP_LOW_POWER_SUPPLY # This should be the safe default
	matchingNetwork::Integer = 1
end
SimulatedAmplifierParams(dict::Dict) = params_from_dict(SimulatedAmplifierParams, dict)

Base.@kwdef mutable struct SimulatedAmplifier <: Amplifier
  @add_device_fields SimulatedAmplifierParams

  state::Bool = false
  mode::AmplifierMode = AMP_VOLTAGE_MODE
  powerSupplyMode::AmplifierPowerSupplyMode = AMP_LOW_POWER_SUPPLY
  network::Integer = 1
end

function _init(amp::SimulatedAmplifier)
  # Set values given by configuration
	mode(amp, amp.params.mode)
	powerSupplyMode(amp, amp.params.powerSupplyMode)
	matchingNetwork(amp, amp.params.matchingNetwork)
end

checkDependencies(amp::SimulatedAmplifier) = true

Base.close(amp::SimulatedAmplifier) = nothing

state(amp::SimulatedAmplifier) = amp.state
turnOn(amp::SimulatedAmplifier) = amp.state = true
turnOff(amp::SimulatedAmplifier) = amp.state = false
mode(amp::SimulatedAmplifier) = amp.mode
mode(amp::SimulatedAmplifier, mode::AmplifierMode) = amp.mode = mode
powerSupplyMode(amp::SimulatedAmplifier) = amp.powerSupplyMode
powerSupplyMode(amp::SimulatedAmplifier, mode::AmplifierPowerSupplyMode) = amp.powerSupplyMode = mode
matchingNetwork(amp::SimulatedAmplifier) = amp.network
matchingNetwork(amp::SimulatedAmplifier, network::Integer) = amp.network = network
temperature(amp::SimulatedAmplifier) = 25.0u"°C"
channelId(amp::SimulatedAmplifier) = amp.params.channelID
