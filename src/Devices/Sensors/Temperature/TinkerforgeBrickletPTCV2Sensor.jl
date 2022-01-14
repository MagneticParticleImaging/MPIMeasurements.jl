export TinkerforgeBrickletPTCV2Params, TinkerforgeBrickletPTCV2

Base.@kwdef struct TinkerforgeBrickletPTCV2Params <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletPTCV2Params(dict::Dict) = params_from_dict(TinkerforgeBrickletPTCV2Params, dict)

Base.@kwdef mutable struct TinkerforgeBrickletPTCV2 <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletPTCV2Params
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickletPTCV2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletPTCV2)
  @debug "Initializing Tinkerforge distance sensor unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletPTCV2(disp.params.uid, disp.ipcon)

  disp.present = true
end

neededDependencies(::TinkerforgeBrickletPTCV2) = []
optionalDependencies(::TinkerforgeBrickletPTCV2) = []
Base.close(disp::TinkerforgeBrickletPTCV2) = PyTinkerforge.disconnect(disp.ipcon)

numChannels(sensor::TinkerforgeBrickletPTCV2) = 1
getTemperatures(sensor::TinkerforgeBrickletPTCV2)::Vector{typeof(1u"°C")} = [getTemperature(sensor, 1)]
getTemperature(sensor::TinkerforgeBrickletPTCV2, channel::Int)::typeof(1u"°C") = (PyTinkerforge.get_temperature(sensor)/100.0)*u"°C"