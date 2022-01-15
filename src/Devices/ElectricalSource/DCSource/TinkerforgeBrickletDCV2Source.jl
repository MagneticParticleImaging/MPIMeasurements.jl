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
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletDCV2SourceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickletDCV2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function init(source::TinkerforgeBrickletDCV2Source)
  @debug "Initializing Tinkerforge DC source unit with ID `$(disp.deviceID)`."

  source.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(source.ipcon, source.params.host, source.params.port)
  source.deviceInternal = PyTinkerforge.BrickletDCV2(source.params.uid, source.ipcon)

  set_pwm_frequency(source, ustrip(u"Hz", source.params.pwmFrequency))
  set_motion(source, source.params.acceleration, source.params.acceleration)
  
  disp.present = true
  return
end

neededDependencies(::TinkerforgeBrickletDCV2Source) = []
optionalDependencies(::TinkerforgeBrickletDCV2Source) = []
Base.close(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.disconnect(source.ipcon)

externalVoltage(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.get_external_input_voltage(source)u"mV"
enable(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.set_enabled(source, true)
disable(source::TinkerforgeBrickletDCV2Source) = PyTinkerforge.set_enabled(source, true)
output(source::TinkerforgeBrickletDCV2Source, value::typeof(1.0u"V")) = set_velocity(source, upreferred(value/externalVoltage(source))*32767)