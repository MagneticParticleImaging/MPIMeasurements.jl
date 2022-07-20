export ArduinoSurveillanceUnitExternalTemp, ArduinoSurveillanceUnitExternalTempParams, ArduinoSurveillanceUnitExternalTempPortParams, ArduinoSurveillanceUnitExternalTempPoolParams

abstract type ArduinoSurveillanceUnitExternalTempParams <: DeviceParams end

Base.@kwdef struct ArduinoSurveillanceUnitExternalTempPortParams <: ArduinoSurveillanceUnitExternalTempParams
  portAdress::String
  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoSurveillanceUnitExternalTempPortParams(dict::Dict) = params_from_dict(ArduinoSurveillanceUnitExternalTempPortParams, dict)


Base.@kwdef struct ArduinoSurveillanceUnitExternalTempPoolParams <: ArduinoSurveillanceUnitExternalTempParams
  description::String
  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoSurveillanceUnitExternalTempPoolParams(dict::Dict) = params_from_dict(ArduinoSurveillanceUnitExternalTempPoolParams, dict)


Base.@kwdef mutable struct ArduinoSurveillanceUnitExternalTemp <: ArduinoSurveillanceUnit
  @add_device_fields ArduinoSurveillanceUnitExternalTempParams

  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end

Base.close(su::ArduinoSurveillanceUnitExternalTemp) = close(su.ard)

sendCommand(su::ArduinoSurveillanceUnitExternalTemp, cmdString::String) = sendCommand(su.ard, cmdString) 

neededDependencies(::ArduinoSurveillanceUnitExternalTemp) = [ArduinoTemperatureSensor] # could in theory be generic temp sensor
optionalDependencies(::ArduinoSurveillanceUnitExternalTemp) = [SerialPortPool]

function _init(su::ArduinoSurveillanceUnitExternalTemp)
  params = gauss.params
  sd = initSerialDevice(su, params)
  @info "Connection to ArduinoSurveillanceUnit established."        
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  su.ard = ard
end

function initSerialDevice(su::ArduinoSurveillanceUnitExternalTemp, params::ArduinoSurveillanceUnitExternalTempPortParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(gauss, sd)
  return sd
end

function initSerialDevice(su::ArduinoSurveillanceUnitExternalTemp, params::ArduinoSurveillanceUnitExternalTempPoolParams)
  sd = initSerialDevice(su, params.description)
  checkSerialDevice(su, sd)
  return sd
end

function checkSerialDevice(su::ArduinoSurveillanceUnitExternalTemp, sd::SerialDevice)
  try
    reply = query(sd, "!VERSION*")
    if !(startswith(reply, "SURVBOX:3"))
        close(sd)
        throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
    end
    return sd
  catch e
    throw(ScannerConfigurationError("Could not verify if connected to correct device"))
  end
end


getTemperatureSensor(su::ArduinoSurveillanceUnitExternalTemp) = dependency(su, ArduinoTemperatureSensor)

function getTemperatures(su::ArduinoSurveillanceUnitExternalTemp; names::Bool=false)
  sensor = getTemperatureSensor(su)
  return getTemperatures(sensor, names = names)
end

function getStatus(su::ArduinoSurveillanceUnitExternalTemp)
  status = sendCommand(su,"GET:STATS")
  return status
end

function resetDAQ(su::ArduinoSurveillanceUnitExternalTemp)
  ACQ = sendCommand(su,"RESET:RP")
  checkACQ(su, ACQ)
end

hasResetDAQ(su::ArduinoSurveillanceUnitExternalTemp) = true