export HubertAmplifier, HubertAmplifierParams
abstract type HubertAmplifierParams <: DeviceParams end

Base.@kwdef struct HubertAmplifierPortParams <: HubertAmplifierParams
	channelID::String
	port::String
	@add_serial_device_fields nothing
	mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	voltageMode::AmplifierVoltageMode = AMP_LOW_VOLTAGE_MODE # This should be the safe default
	matchingNetwork::Integer = 1
	warmUpDelay::Float64 = 0.2
end
HubertAmplifierPortParams(dict::Dict) = params_from_dict(HubertAmplifierPortParams, dict)

Base.@kwdef struct HubertAmplifierPoolParams <: HubertAmplifierParams
	channelID::String
	description::String
	@add_serial_device_fields nothing
	mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	voltageMode::AmplifierVoltageMode = AMP_LOW_VOLTAGE_MODE # This should be the safe default
	matchingNetwork::Integer = 1
	warmUpDelay::Float64 = 0.2
end
HubertAmplifierPoolParams(dict::Dict) = params_from_dict(HubertAmplifierPoolParams, dict)


Base.@kwdef mutable struct HubertAmplifier <: Amplifier
	@add_device_fields HubertAmplifierParams

  driver::Union{SerialDevice, Missing} = missing
end

function _init(amp::HubertAmplifier)
	@warn "The code for the Hubert amplifier has not yet been tested within MPIMeasurements!"

	amp.driver = initSerialDevice(amp, amp.params)

	_hubertSetStartupParameters(amp)

	# Set values given by configuration
	mode(amp, amp.params.mode)
	voltageMode(amp, amp.params.voltageMode)
	matchingNetwork(amp, amp.params.matchingNetwork)
end

function initSerialDevice(amp::HubertAmplifier, params::HubertAmplifierPortParams)
  sd = SerialDevice(params.port; serial_device_splatting(params)...)
  return sd
end

function initSerialDevice(amp::HubertAmplifier, params::HubertAmplifierPoolParams)
  return initSerialDevice(amp, params.description)
end

checkDependencies(amp::HubertAmplifier) = true

Base.close(amp::HubertAmplifier) = close(amp.driver)

# main communication function
function _hubertSerial(amp::HubertAmplifier, input::Array{UInt8}, ack::Array{UInt8})

	output = zeros(UInt8, size(ack))
	answer_hex = _hubertSerial!(amp, input, output)

	if answer_hex == ack
		@debug "Hubert acknowleged: '$(answer_hex)' set."
	else
		@error "Hubert: Serial communication error. Expected '$(ack)', received '$(answer_hex)'"	
	end

	return nothing
end

function _hubertSerial!(amp::HubertAmplifier, input::Array{UInt8}, output::Array{UInt8}) #for querys
	query!(amp.driver, input, output)
	return output
end

function _hubertSetStartupParameters(amp::HubertAmplifier)
	# EINschaltparameter - werde nur beim Einschalten aktualisiert 
	input = UInt8[	0x0B, 0x2E, #setzten der erw. Einstellung auf einmal
					0x00,		#1. Strommessbereich: high 00, low 01 - use high! 		
					0x07,		#2. RC_network: depends ... (05 or 07). 07: trimmed
					0x00,		#3. Mode: voltage 00, current 01 -!!DO YOU HAVE A LOAD CONNECTED?!!
					0x00,		#4. 00 (empty)
					0x0f,		#5. Highbyte Limit Control (0x00 - 0x0F)
					0xff,		#6. Lowbyte Limit Control (0x00 - 0xFF)
					0x01,		#7. Interlock: latching 00, live 01 - needs to be live for RP interlock
					0x00,		#8. Limit Control: current 00, voltage 01
					0x09]		#9. Betriebsspann. mid: 05, high: 09 - do not use auto (01)!
	ack = UInt8[0x2e]
	_hubertSerial(amp, input, ack)
	sleep(0.1)
	input = UInt8[0x03, 0x5D, 0x00] #sensing needs to be off (otherwise DC offset) - but Huberts jumps straight to Overvoltage after Interlock.
	ack = UInt8[0x5D]
	_hubertSerial(amp, input, ack)
	return nothing
end

function state(amp::HubertAmplifier)
	input = UInt8[0x02, 0x10]
	output = zeros(UInt8, 1)
	return _hubertSerial!(amp, input, output)
end

function turnOn(amp::HubertAmplifier)
	@info "Amplifier $(amp.deviceID) enabled"
	input = UInt8[0x03, 0x35, 0x01]
	ack   = UInt8[0x01]
	_hubertSerial(amp, input, ack)
	sleep(amp.params.warmUpDelay)
	return nothing
end


function turnOff(amp::HubertAmplifier)
	@info "Amplifier $(amp.deviceID) disabled"
	input = UInt8[0x03, 0x35, 0x00]
	ack   = UInt8[0x00]
	_hubertSerial(amp, input, ack)
	return nothing
end

mode(amp::HubertAmplifier) = @error "Getting the current amplifier mode is not yet supported."

function mode(amp::HubertAmplifier, mode::AmplifierMode)
	#Mode: voltage 00, current 01
	if mode == AMP_CURRENT_MODE
		@warn "Current mode temporarily disabled. Never start without a load."
		#input = UInt8[0x03, 0x2A, 0x01]
		return nothing
	elseif mode == AMP_VOLTAGE_MODE
		input = UInt8[0x03, 0x2A, 0x00]
	else
		throw(ScannerConfigurationError("Unsupported mode for Hubert amplifier: $mode."))
	end

	ack = UInt8[0x2A]
	_hubertSerial(amp, input, ack)

	return nothing
end

voltageMode(amp::HubertAmplifier) = @error "Getting the current amplifier voltage mode is not yet supported."

function voltageMode(amp::HubertAmplifier, mode::AmplifierVoltageMode)
	#high is required, may set to low for below 15mt [??? toDo: after cal]
	#9. Betriebsspann. mid: 05, high: 09 - do not use auto (01)!
	if mode == AMP_HIGH_VOLTAGE_MODE
		input = UInt8[0x03, 0x54, 0x09]
	elseif mode == AMP_LOW_VOLTAGE_MODE
		input = UInt8[0x03, 0x54, 0x05]
	else
		throw(ScannerConfigurationError("Unsupported voltage mode for Hubert amplifier: $mode."))
	end

	ack = UInt8[0x54]
	_hubertSerial(amp, input, ack)

	return nothing
end

matchingNetwork(amp::HubertAmplifier) = @error "Getting the current amplifier network is not yet supported."

function matchingNetwork(amp::HubertAmplifier, network::Integer)
	#2. RC_network: (05 or 07). 07: trimmed //specific for THIS hubert amplifier
	if network >= 1 && network <= 7
		input = UInt8[0x03, 0x29, UInt8(network)]
		ack = UInt8[network]
		_hubertSerial(amp, input, ack)
	else
		throw(ScannerConfigurationError("Hubert: '$(network)' is not a RC-Network {1...7}."))
	end

	return nothing
end

function temperature(amp::HubertAmplifier)
	input = UInt8[0x02, 0x04]
	output = zeros(UInt8, 1)
	hex = _hubertSerial!(amp, input, output)
	return Int(hex[1])
end

channelId(amp::HubertAmplifier) = amp.params.channelID
