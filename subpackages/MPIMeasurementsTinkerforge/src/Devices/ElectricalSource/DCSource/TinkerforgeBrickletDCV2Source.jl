export TinkerforgeBrickletDCV2SourceParams, TinkerforgeBrickletDCV2Source

Base.@kwdef struct TinkerforgeBrickletDCV2SourceParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String

  pwmFrequency::typeof(1.0u"Hz") = 15000u"Hz"
  acceleration::Integer = 16384 # 50 % as default
end
TinkerforgeBrickletDCV2SourceParams(dict::Dict) = params_from_dict(TinkerforgeBrickletDCV2SourceParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletDCV2Source <: Display
  MPIMeasurements.@add_device_fields TinkerforgeBrickletDCV2SourceParams

  deviceInternal::Union{PyTinkerforge.BrickletDCV2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(source::TinkerforgeBrickletDCV2Source)
  @debug "Initializing Tinkerforge DC source unit with ID `$(disp.deviceID)`."

  source.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(source.ipcon, source.params.host, source.params.port)
  source.deviceInternal = PyTinkerforge.BrickletDCV2(source.params.uid, source.ipcon)

  set_pwm_frequency(source, ustrip(u"Hz", source.params.pwmFrequency))
  set_motion(source, source.params.acceleration, source.params.acceleration)
  
  disp.present = true
  return
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickletDCV2Source) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickletDCV2Source) = []
Base.close(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.disconnect(source.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickletDCV2Source) = true

externalVoltage(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.get_external_input_voltage(source)u"mV"
enable(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.set_enabled(source, true)
disable(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.set_enabled(source, true)
output(source::TinkerforgeBrickletDCV2Source, value::typeof(1.0u"V")) = set_velocity(source, upreferred(value/externalVoltage(source))*32767)