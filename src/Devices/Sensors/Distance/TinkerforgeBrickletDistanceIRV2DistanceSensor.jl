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
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletDistanceIRV2DistanceSensorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{BrickletDistanceIRV2, Missing} = missing
  ipcon::Union{IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor)
  @debug "Initializing Tinkerforge display unit with ID `$(disp.deviceID)`."

  disp.ipcon = IPConnection()
  PyTinkerforge.connect(disp.ipcon, disp.params.host, disp.params.port)
  disp.deviceInternal = BrickletDistanceIRV2(disp.params.uid, disp.ipcon)

  disp.present = true

  # Set the configured moving average filter length
  movingAverageLength(disp, disp.params.movingAverageLength)
end

checkDependencies(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = true

Base.close(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = disconnect(disp.ipcon)

distance(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = get_distance(disp.deviceInternal)
movingAverageLength(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor) = get_moving_average_configuration(disp.deviceInternal)
movingAverageLength(disp::TinkerforgeBrickletDistanceIRV2DistanceSensor, length_::Integer) = set_moving_average_configuration(disp.deviceInternal, length_)
