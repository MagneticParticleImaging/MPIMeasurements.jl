export TinkerforgeBrickletOLED128x64V2DisplayParams, TinkerforgeBrickletOLED128x64V2Display

Base.@kwdef struct TinkerforgeBrickletOLED128x64V2DisplayParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletOLED128x64V2DisplayParams(dict::Dict) = params_from_dict(TinkerforgeBrickletOLED128x64V2DisplayParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletOLED128x64V2Display <: Display
  MPIMeasurements.@add_device_fields TinkerforgeBrickletOLED128x64V2DisplayParams

  deviceInternal::Union{PyTinkerforge.BrickletOLED128x64V2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(disp::TinkerforgeBrickletOLED128x64V2Display)
  @debug "Initializing Tinkerforge display unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletOLED128x64V2(disp.params.uid, disp.ipcon)

  disp.present = true
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickletOLED128x64V2Display) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickletOLED128x64V2Display) = []
Base.close(disp::TinkerforgeBrickletOLED128x64V2Display) = PyTinkerforge.disconnect(disp.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickletOLED128x64V2Display) = true

clear(disp::TinkerforgeBrickletOLED128x64V2Display) = PyTinkerforge.clear_display(disp.deviceInternal)
writeLine(disp::TinkerforgeBrickletOLED128x64V2Display, row::Integer, column::Integer, message::String) = PyTinkerforge.write_line(disp.deviceInternal, row, column, message)