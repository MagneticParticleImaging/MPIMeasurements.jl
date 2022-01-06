export TinkerforgeBrickletLCD20x4DisplayParams, TinkerforgeBrickletLCD20x4Display

Base.@kwdef struct TinkerforgeBrickletLCD20x4DisplayParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletLCD20x4DisplayParams(dict::Dict) = params_from_dict(TinkerforgeBrickletLCD20x4DisplayParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletLCD20x4Display <: Display
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletLCD20x4DisplayParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickletLCD20x4, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletLCD20x4Display)
  @debug "Initializing Tinkerforge display unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletLCD20x4(disp.params.uid, disp.ipcon)

  disp.present = true
end

checkDependencies(disp::TinkerforgeBrickletLCD20x4Display) = true

Base.close(disp::TinkerforgeBrickletLCD20x4Display) = PyTinkerforge.disconnect(disp.ipcon)

clear(disp::TinkerforgeBrickletLCD20x4Display) = PyTinkerforge.clear_display(disp.deviceInternal)
writeLine(disp::TinkerforgeBrickletLCD20x4Display, row::Integer, column::Integer, message::String) = PyTinkerforge.write_line(disp.deviceInternal, row, column, message)
hasBacklight(disp::TinkerforgeBrickletLCD20x4Display) = true
setBacklight(disp::TinkerforgeBrickletLCD20x4Display, state::Bool) = state ? PyTinkerforge.backlight_on(disp.deviceInternal) : PyTinkerforge.backlight_off(disp.deviceInternal)