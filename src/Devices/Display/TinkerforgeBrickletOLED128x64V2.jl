export TinkerforgeBrickletOLED128x64V2DisplayParams, TinkerforgeBrickletOLED128x64V2Display

Base.@kwdef struct TinkerforgeBrickletOLED128x64V2DisplayParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletOLED128x64V2DisplayParams(dict::Dict) = params_from_dict(TinkerforgeBrickletOLED128x64V2DisplayParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletOLED128x64V2Display <: Display
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletOLED128x64V2DisplayParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickletOLED128x64V2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletOLED128x64V2Display)
  @debug "Initializing Tinkerforge display unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletOLED128x64V2(disp.params.uid, disp.ipcon)

  disp.present = true
end

checkDependencies(disp::TinkerforgeBrickletOLED128x64V2Display) = true

Base.close(disp::TinkerforgeBrickletOLED128x64V2Display) = PyTinkerforge.disconnect(disp.ipcon)

clear(disp::TinkerforgeBrickletOLED128x64V2Display) = PyTinkerforge.clear_display(disp.deviceInternal)
writeLine(disp::TinkerforgeBrickletOLED128x64V2Display, row::Integer, column::Integer, message::String) = PyTinkerforge.write_line(disp.deviceInternal, row, column, message)