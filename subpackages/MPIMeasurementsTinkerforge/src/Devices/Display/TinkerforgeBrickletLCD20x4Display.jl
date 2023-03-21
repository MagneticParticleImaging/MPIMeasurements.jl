export TinkerforgeBrickletLCD20x4DisplayParams, TinkerforgeBrickletLCD20x4Display

Base.@kwdef struct TinkerforgeBrickletLCD20x4DisplayParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletLCD20x4DisplayParams(dict::Dict) = params_from_dict(TinkerforgeBrickletLCD20x4DisplayParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletLCD20x4Display <: Display
  MPIMeasurements.@add_device_fields TinkerforgeBrickletLCD20x4DisplayParams

  deviceInternal::Union{PyTinkerforge.BrickletLCD20x4, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(disp::TinkerforgeBrickletLCD20x4Display)
  @debug "Initializing Tinkerforge display unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletLCD20x4(disp.params.uid, disp.ipcon)

  disp.present = true
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickletLCD20x4Display) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickletLCD20x4Display) = []
Base.close(disp::TinkerforgeBrickletLCD20x4Display) = PyTinkerforge.disconnect(disp.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickletLCD20x4Display) = true

MPIMeasurements.clear(disp::TinkerforgeBrickletLCD20x4Display) = PyTinkerforge.clear_display(disp.deviceInternal)
MPIMeasurements.writeLine(disp::TinkerforgeBrickletLCD20x4Display, row::Integer, column::Integer, message::String) = PyTinkerforge.write_line(disp.deviceInternal, row, column, message)
MPIMeasurements.hasBacklight(disp::TinkerforgeBrickletLCD20x4Display) = true
MPIMeasurements.setBacklight(disp::TinkerforgeBrickletLCD20x4Display, state::Bool) = state ? PyTinkerforge.backlight_on(disp.deviceInternal) : PyTinkerforge.backlight_off(disp.deviceInternal)