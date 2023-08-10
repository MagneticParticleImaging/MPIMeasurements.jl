export TinkerforgeBrickletPTCParams, TinkerforgeBrickletPTC

Base.@kwdef struct TinkerforgeBrickletPTCParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletPTCParams(dict::Dict) = params_from_dict(TinkerforgeBrickletPTCParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletPTC <: TemperatureSensor
  MPIMeasurements.@add_device_fields TinkerforgeBrickletPTCParams

  deviceInternal::Union{PyTinkerforge.BrickletPTC, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(disp::TinkerforgeBrickletPTC)
  @debug "Initializing Tinkerforge distance sensor unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletPTC(disp.params.uid, disp.ipcon)

  disp.present = true
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickletPTC) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickletPTC) = []
Base.close(disp::TinkerforgeBrickletPTC) = PyTinkerforge.disconnect(disp.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickletPTC) = true

MPIMeasurements.numChannels(sensor::TinkerforgeBrickletPTC) = 1
MPIMeasurements.getTemperatures(sensor::TinkerforgeBrickletPTC)::Vector{typeof(1u"°C")} = [getTemperature(sensor, 1)]
MPIMeasurements.getTemperature(sensor::TinkerforgeBrickletPTC, channel::Int)::typeof(1u"°C") = (PyTinkerforge.get_temperature(sensor)/100.0)*u"°C"