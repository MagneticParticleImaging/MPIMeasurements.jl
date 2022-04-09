export SimulatedAmplifier, SimulatedAmplifierParams

Base.@kwdef struct SimulatedAmplifierParams <: DeviceParams
  channelID::String
  mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	voltageMode::AmplifierVoltageMode = AMP_LOW_VOLTAGE_MODE # This should be the safe default
	matchingNetwork::Integer = 1
end
SimulatedAmplifierParams(dict::Dict) = params_from_dict(SimulatedAmplifierParams, dict)

Base.@kwdef mutable struct SimulatedAmplifier <: Amplifier
  @add_device_fields SimulatedAmplifierParams

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
channelId(amp::SimulatedAmplifier) = amp.params.channelID
