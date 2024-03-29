export TinkerforgeBrickDCSourceParams, TinkerforgeBrickDCSource

Base.@kwdef struct TinkerforgeBrickDCSourceParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String

  pwmFrequency::typeof(1.0u"Hz") = 15000u"Hz"
  acceleration::Integer = 16384 # 50 % as default
end
TinkerforgeBrickDCSourceParams(dict::Dict) = params_from_dict(TinkerforgeBrickDCSourceParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickDCSource <: Display
  MPIMeasurements.@add_device_fields TinkerforgeBrickDCSourceParams

  deviceInternal::Union{PyTinkerforge.BrickDC, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(source::TinkerforgeBrickDCSource)
  @debug "Initializing Tinkerforge DC source unit with ID `$(disp.deviceID)`."

  source.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(source.ipcon, source.params.host, source.params.port)
  source.deviceInternal = PyTinkerforge.BrickDC(source.params.uid, source.ipcon)

  set_pwm_frequency(source, ustrip(u"Hz", source.params.pwmFrequency))
  set_acceleration(source, source.params.acceleration)
  
  disp.present = true
  return
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickDCSource) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickDCSource) = []
Base.close(source::TinkerforgeBrickDCSource) = PyTinkerforge.disconnect(source.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickDCSource) = true

externalVoltage(source::TinkerforgeBrickDCSource) = PyTinkerforge.get_external_input_voltage(source)u"mV"
enable(source::TinkerforgeBrickDCSource) = PyTinkerforge.enable(source)
disable(source::TinkerforgeBrickDCSource) = PyTinkerforge.disable(source)
output(source::TinkerforgeBrickDCSource, value::typeof(1.0u"V")) = set_velocity(source, upreferred(value/externalVoltage(source))*32767)
