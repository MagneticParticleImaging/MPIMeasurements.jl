export HubertAmplifier, HubertAmplifierParams, HubertAmplifierPoolParams, HubertAmplifierPortParams
abstract type HubertAmplifierParams <: DeviceParams end

@enum HubertVersion begin
	A1110E
	A1110QE
end

Base.@kwdef struct HubertAmplifierPortParams <: HubertAmplifierParams
	"ID of the tx channel this amplifier is connected to"
	channelID::String
	"Serial port address of the amplifier"
	port::String
	@add_serial_device_fields nothing
	mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	"Power supply level the amplifier should be initialized with, must contain `low`, `mid` or `high`"
	powerSupplyMode::AmplifierPowerSupplyMode = AMP_LOW_POWER_SUPPLY # This should be the safe default
	"Idx of the matching network to use in current mode"
	matchingNetwork::Integer = 1
	"Delay in s to wait after enabling the output"
	warmUpDelay::Float64 = 0.2
end

function HubertAmplifierPortParams(dict::Dict)
	if haskey(dict, "voltageMode")
		@warn "The parameter `voltageMode` for the Hubert amplifiers is deprecated, please use `powerSupplyMode` instead!"
		dict["powerSupplyMode"] = dict["voltageMode"]
		pop!(dict, "voltageMode")
	end
	return params_from_dict(HubertAmplifierPortParams, dict)
end

Base.@kwdef struct HubertAmplifierPoolParams <: HubertAmplifierParams
	"string, required, ID of the tx channel this amplifier is connected to"
	channelID::String
	"string, required, Description of the amps serial port to find in pool"
	description::String
	@add_serial_device_fields nothing
	mode::AmplifierMode = AMP_VOLTAGE_MODE # This should be the safe default
	"Power supply level the amplifier should be initialized with, must contain `low`, `mid` or `high`"
	powerSupplyMode::AmplifierPowerSupplyMode = AMP_LOW_POWER_SUPPLY # This should be the safe default
	"Idx of the matching network to use in current mode"
	matchingNetwork::Integer = 1
	"Delay in s to wait after enabling the output"
	warmUpDelay::Float64 = 0.2
end

function HubertAmplifierPoolParams(dict::Dict)
	if haskey(dict, "voltageMode")
		@warn "The parameter `voltageMode` for the Hubert amplifiers is deprecated, please use `powerSupplyMode` instead!"
		dict["powerSupplyMode"] = dict["voltageMode"]
		pop!(dict, "voltageMode")
	end
	return params_from_dict(HubertAmplifierPoolParams, dict)
end

Base.@kwdef mutable struct HubertAmplifier <: Amplifier
	@add_device_fields HubertAmplifierParams

  driver::Union{SerialDevice, Missing} = missing
	model::Union{HubertVersion, Missing} = missing
end

function _hubertModel(amp::HubertAmplifier)
	# Undocumented command, suggested by Hubert support via E-Mail
	answer = String(_hubertSerial(amp, UInt8[0x02,0x50]))
	if answer == "P111MAIN"
		return A1110E
	elseif answer == "P111MAINQE"
		return A1110QE
	else
		error("Unknown hubert model $(answer)! This should not happen...")
	end
end

struct HubertStatus
	ready::Bool
	overload::Bool
	overtemperature::Bool
	interlockActive::Bool
	supplyVoltage::Union{Missing,AmplifierPowerSupplyMode}
	on::Bool
	function HubertStatus(state::UInt8, model::HubertVersion=A1110QE)
		if model == A1110E
			supplyVoltage = AmplifierPowerSupplyMode((state&(0b11 << 5))>>5)
		else
			supplyVoltage = missing
		end
		new(state&(0x1 << 0) != 0, state&(0x1 << 1)!= 0, state&(0x1 << 2)!= 0, state&(0x1 << 4)!= 0,supplyVoltage, state&(0x1 << 7)!= 0)
	end
end
status_symbol(status::Bool, positive::Bool=true)= if status&&positive; styled"{green:✔}" elseif status&&!positive; styled"{red,bold:!}" elseif !status&&positive; styled"{red:✘}" else styled"{green,bold:-}" end

function Base.show(io::IO, st::HubertStatus)
    println(io, "HubertStatus:")
    println(io, "  Ready:             ", status_symbol(st.ready))
    println(io, "  Overload:          ", status_symbol(st.overload, false))
    println(io, "  Overtemperature:   ", status_symbol(st.overtemperature,false))
    println(io, "  Interlock Active:  ", status_symbol(st.interlockActive,false))
    println(io, "  Supply Voltage:    ", st.supplyVoltage)  # Keine Farbformatierung
    println(io, "  On:                ", status_symbol(st.on))
end

function _init(amp::HubertAmplifier)
	amp.driver = initSerialDevice(amp, amp.params)
	amp.model = _hubertModel(amp)

	# Set values given by configuration
	mode(amp, amp.params.mode)
	powerSupplyMode(amp, amp.params.powerSupplyMode)
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

function _hubertSerial(amp::HubertAmplifier, input::Array{UInt8})
	lock(amp.driver.sdLock)
	try
		sp_flush(amp.driver.sp, SP_BUF_INPUT)
		send(amp.driver,input)
		sleep(0.1)
		res = nonblocking_read(amp.driver.sp)
		sp_flush(amp.driver.sp, SP_BUF_INPUT)
		return res
	finally
		unlock(amp.driver.sdLock)
	end
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

function _hubertGetSettings(amp::HubertAmplifier)
	input = UInt8[0x02, 0x38]
	output = zeros(UInt8, 10)
	return _hubertSerial!(amp, input, output)
end

function _hubertGetStartupSettings(amp::HubertAmplifier)
	input = UInt8[0x02, 0x22]
	output = zeros(UInt8, 1)
	return _hubertSerial!(amp, input, output)
end

function _hubertGetExtendedStartupSettings(amp::HubertAmplifier)
	input = UInt8[0x02, 0x2F]
	output = zeros(UInt8, 8)
	return _hubertSerial!(amp, input, output)
end

function state(amp::HubertAmplifier)
	input = UInt8[0x02, 0x10]
	output = zeros(UInt8, 1)
	return HubertStatus(_hubertSerial!(amp, input, output)[], _hubertModel(amp))
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

function mode(amp::HubertAmplifier)
	res = _hubertSerial!(amp, UInt8[0x02,0x38], zeros(UInt8,3))
	if res[3] == 0x00
		return AMP_VOLTAGE_MODE
	elseif res[3] == 0x01
		return AMP_CURRENT_MODE
	else
		error("Unknown response from Hubert: $(res[3])")
	end
end

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

function powerSupplyMode(amp::HubertAmplifier)
	if _hubertModel(amp) == A1110E
		return state(amp).supplyVoltage
	elseif _hubertModel(amp) == A1110QE
		res = _hubertSerial!(amp, UInt8[0x02,0x38], zeros(UInt8,12))
		if res[12] == 0x05
			return AMP_LOW_POWER_SUPPLY
		elseif res[12] == 0x09
			return AMP_HIGH_POWER_SUPPLY
		else
			error("Amplifier seems to be in auto mode or has different supply voltages configured for + and - (code: $(res[12])). This is not supported by MPIMeasurements!")
		end
	end
end

function powerSupplyMode(amp::HubertAmplifier, mode::AmplifierPowerSupplyMode)
	if _hubertModel(amp) == A1110QE
		#high is required, may set to low for below 15mt [??? toDo: after cal]
		#9. Betriebsspann. mid: 05, high: 09 - do not use auto (01)!
		if mode == AMP_HIGH_POWER_SUPPLY
			input = UInt8[0x03, 0x54, 0x09]
		elseif mode == AMP_LOW_POWER_SUPPLY
			input = UInt8[0x03, 0x54, 0x05]
		else
			throw(ScannerConfigurationError("Unsupported voltage mode for Hubert amplifier $(_hubertModel(amp)): $mode."))
		end

		ack = UInt8[0x54]
		_hubertSerial(amp, input, ack)
	elseif _hubertModel(amp) == A1110E
		orig_timeout = amp.driver.timeout_ms
		amp.driver.timeout_ms = 10000 # changing the power supply takes a moment on the A1110E Huberts
		if mode==AMP_HIGH_POWER_SUPPLY
			_hubertSerial(amp, UInt8[0x02, 0x05], UInt8[0x05])
		elseif mode==AMP_MID_POWER_SUPPLY
			_hubertSerial(amp, UInt8[0x02, 0x27], UInt8[0x27])
		elseif mode==AMP_LOW_POWER_SUPPLY
			_hubertSerial(amp, UInt8[0x02, 0x06], UInt8[0x06])
		else
			throw(ScannerConfigurationError("Unsupported voltage mode for Hubert amplifier $(_hubertModel(amp)): $mode."))
		end
		amp.driver.timeout_ms = orig_timeout
	end
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
	return Int(hex[1])*u"°C"
end

function currentPowerLossPercent(amp::HubertAmplifier)
	if _hubertModel(amp) == A1110QE
		@warn "The A1110-QE does not support power loss monitoring!"
		return 0
	end
	hex = _hubertSerial!(amp, UInt8[0x02,0x0E], UInt8[0x0])
	return Int(hex[1])/250*100
end

hubertId(amp::HubertAmplifier) = String(_hubertSerial(amp, UInt8[0x02,0x51])) 
function hubertId!(amp::HubertAmplifier, newID::String) 
	_hubertSerial(amp, [UInt8[0x82,0x52]; Vector{UInt8}(newID); repeat(UInt8[0x0], 128-length(newID))], UInt8[0x52])
	return hubertId(amp)
end

channelId(amp::HubertAmplifier) = amp.params.channelID
