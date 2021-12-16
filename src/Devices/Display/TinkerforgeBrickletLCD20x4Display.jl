export TinkerforgeBrickletLCD20x4DisplayParams, TinkerforgeBrickletLCD20x4Display

Base.@kwdef struct TinkerforgeBrickletLCD20x4DisplayParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
end
TinkerforgeBrickletLCD20x4DisplayParams(dict::Dict) = params_from_dict(TinkerforgeBrickletLCD20x4DisplayParams, dict)

Base.@kwdef mutable struct TinkerforgeBrickletLCD20x4DisplayBrick <: StepperMotor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeBrickletLCD20x4DisplayParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  brick::Union{BrickletLCD20x4, Missing} = missing
  ipcon::Union{IPConnection, Missing} = missing
end

function init(disp::TinkerforgeBrickletLCD20x4Display)
  @debug "Initializing Tinkerforge silent stepper unit with ID `$(disp.deviceID)`."

  disp.ipcon = IPConnection(disp.params.host, disp.params.port)
  disp.brick = BrickletLCD20x4(disp.params.uid, disp.ipcon)
end

checkDependencies(disp::TinkerforgeBrickletLCD20x4Display) = true

Base.close(disp::TinkerforgeBrickletLCD20x4Display) = disconnect(disp.ipcon)