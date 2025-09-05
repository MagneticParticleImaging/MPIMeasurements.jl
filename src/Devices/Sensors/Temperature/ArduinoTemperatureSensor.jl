export ArduinoTemperatureSensor, ArduinoTemperatureSensorParams, ArduinoTemperatureSensorPortParams, ArduinoTemperatureSensorPoolParams

abstract type ArduinoTemperatureSensorParams <: DeviceParams end

Base.@kwdef struct ArduinoTemperatureSensorPortParams <: ArduinoTemperatureSensorParams
  portAddress::String
  numSensors::Int
  maxTemps::Vector{Int}
  selectSensors::Vector{Int}
  groupSensors::Vector{Int}
  nameSensors::Vector{String}

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoTemperatureSensorPortParams(dict::Dict) = params_from_dict(ArduinoTemperatureSensorPortParams, dict)

Base.@kwdef struct ArduinoTemperatureSensorPoolParams <: ArduinoTemperatureSensorParams
  description::String
  numSensors::Int
  maxTemps::Vector{Int}
  selectSensors::Vector{Int}
  groupSensors::Vector{Int}
  nameSensors::Vector{String}

  @add_serial_device_fields "#"
  @add_arduino_fields "!" "*"
end
ArduinoTemperatureSensorPoolParams(dict::Dict) = params_from_dict(ArduinoTemperatureSensorPoolParams, dict)


Base.@kwdef mutable struct ArduinoTemperatureSensor <: TemperatureSensor
  @add_device_fields ArduinoTemperatureSensorParams

  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end

neededDependencies(::ArduinoTemperatureSensor) = []
optionalDependencies(::ArduinoTemperatureSensor) = [SerialPortPool]

function _init(sensor::ArduinoTemperatureSensor)
  params = sensor.params
  sd = initSerialDevice(sensor, params)
  @info "Connection to ArduinoTempBox established."        
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  sensor.ard = ard
  try 
    setMaximumTemps(sensor, params.maxTemps)
  catch e
    @warn "Temperature Sensor does not support setMaximumTemps!" error=e
  end
end

function initSerialDevice(sensor::ArduinoTemperatureSensor, params::ArduinoTemperatureSensorPortParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(sensor, sd)
  return sd
end

function initSerialDevice(sensor::ArduinoTemperatureSensor, params::ArduinoTemperatureSensorPoolParams)
  sd = initSerialDevice(sensor, params.description)
  checkSerialDevice(sensor, sd)
  return sd
end

function checkSerialDevice(sensor::ArduinoTemperatureSensor, sd::SerialDevice)
  try
    reply = query(sd, "!VERSION*")
    if !(startswith(reply, "TEMPBOX:3"))
        close(sd)
        throw(ScannerConfigurationError(string("Connected to wrong Device ", reply)))
    end
    return sd
  catch e
    throw(ScannerConfigurationError("Could not verify if connected to correct device"))
  end
end

function numChannels(sensor::ArduinoTemperatureSensor)
  return length(sensor.params.selectSensors)
end

export getChannelNames
function getChannelNames(sensor::ArduinoTemperatureSensor)
  if length(sensor.params.selectSensors) == length(sensor.params.nameSensors) #This should be detected during construction
    return sensor.params.nameSensors[sensor.params.selectSensors]
  else 
    return []
  end
end

function getChannelGroups(sensor::ArduinoTemperatureSensor)
  return sensor.params.groupSensors[sensor.params.selectSensors]
end



function getTemperatures(sensor::ArduinoTemperatureSensor; names::Bool=false)
  temp = retrieveTemps(sensor)
  if length(temp) == sensor.params.numSensors
      if names
          return [temp[sensor.params.selectSensors] sensor.params.nameSensors[sensor.params.selectSensors]]
      else
          return temp[sensor.params.selectSensors]
      end
  else
      return zeros(length(sensor.params.selectSensors))
  end
end

function getTemperature(sensor::ArduinoTemperatureSensor, channel::Int)
  temp = retrieveTemps(sensor)
  return temp[channel]
end

function retrieveTemps(sensor::ArduinoTemperatureSensor)
  TempDelim = "," 
    
  Temps = sendCommand(sensor.ard, "GET:ALLTEMPS")
  Temps = Temps[7:end]  #filter out "TEMPS:" at beginning of answer

  result =  tryparse.(Float64,split(Temps,TempDelim))
  result = map(x -> isnothing(x) ? 0.0 : x, result)
  return result
end

function setMaximumTemps(sensor::ArduinoTemperatureSensor, maxTemps::Array)
    if length(maxTemps) == sensor.params.numSensors
        maxTempString= join(maxTemps, ",")
        ack = sendCommand(sensor.ard, "SET:MAXTEMPS:<"*maxTempString*">")
        # TODO check ack?
        @info "acknowledge of MaxTemps from TempUnit."
    else
        @warn "Please parse a maximum temperature for each sensor" sensor.params.numSensors
    end
end

function getMaximumTemps(sensor::ArduinoTemperatureSensor)
    println(sendCommand(sensor.ard, "GET:MAXTEMPS"))
end

close(sensor::ArduinoTemperatureSensor) = close(sensor.ard)
