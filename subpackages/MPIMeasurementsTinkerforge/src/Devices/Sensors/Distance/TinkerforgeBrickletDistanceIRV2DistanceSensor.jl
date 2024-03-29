export TinkerforgeBrickletDistanceIRV2DistanceSensorParams, TinkerforgeBrickletDistanceIRV2DistanceSensor

Base.@kwdef struct TinkerforgeBrickletDistanceIRV2DistanceSensorParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String

  "Length of the moving average filter."
  movingAverageLength::Integer = 25
end
TinkerforgeBrickletDistanceIRV2DistanceSensorParams(dict::Dict) = params_from_dict(TinkerforgeBrickletDistanceIRV2DistanceSensorParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletDistanceIRV2DistanceSensor <: Display
  MPIMeasurements.@add_device_fields TinkerforgeBrickletDistanceIRV2DistanceSensorParams

  deviceInternal::Union{PyTinkerforge.BrickletDistanceIRV2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing
end

function MPIMeasurements.init(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor)
  @debug "Initializing Tinkerforge distance sensor unit with ID `$(disp.deviceID)`."

  disp.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = PyTinkerforge.BrickletDistanceIRV2(disp.params.uid, disp.ipcon)

  disp.present = true

  # Set the configured moving average filter length
  movingAverageLength(disp, disp.params.movingAverageLength)
end

MPIMeasurements.neededDependencies(::TinkerforgeBrickletDistanceIRV2DistanceSensor) = []
MPIMeasurements.optionalDependencies(::TinkerforgeBrickletDistanceIRV2DistanceSensor) = []
Base.close(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = PyTinkerforge.disconnect(disp.ipcon)
isTinkerforgeDevice(::TinkerforgeBrickletDistanceIRV2DistanceSensor) = true

getDistance(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = PyTinkerforge.get_distance(disp.deviceInternal)*u"mm"
movingAverageLength(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = PyTinkerforge.get_moving_average_configuration(disp.deviceInternal)
movingAverageLength(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor, length_::Integer) = PyTinkerforge.set_moving_average_configuration(disp.deviceInternal, length_)
