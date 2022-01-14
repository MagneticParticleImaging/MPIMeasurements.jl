export TinkerforgeBrickletIndustrialPTCParams, TinkerforgeBrickletIndustrialPTC

Base.@kwdef struct TinkerforgeBrickletIndustrialPTCParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletIndustrialPTCParams(dict::Dict) = params_from_dict(TinkerforgeBrickletIndustrialPTCParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletIndustrialPTC <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletIndustrialPTCParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickletIndustrialPTC, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletIndustrialPTC)
  @debug "Initializing Tinkerforge distance sensor unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletIndustrialPTC(disp.params.uid, disp.ipcon)

  disp.present = true
end

neededDependencies(::TinkerforgeBrickletIndustrialPTC) = []
optionalDependencies(::TinkerforgeBrickletIndustrialPTC) = []
Base.close(disp::TinkerforgeBrickletIndustrialPTC) = PyTinkerforge.disconnect(disp.ipcon)

numChannels(sensor::TinkerforgeBrickletIndustrialPTC) = 1
getTemperatures(sensor::TinkerforgeBrickletIndustrialPTC)::Vector{typeof(1u"°C")} = [getTemperature(sensor, 1)]
getTemperature(sensor::TinkerforgeBrickletIndustrialPTC, channel::Int)::typeof(1u"°C") = (PyTinkerforge.get_temperature(sensor)/100.0)*u"°C"