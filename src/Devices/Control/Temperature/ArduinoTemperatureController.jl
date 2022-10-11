export ArduinoTemperatureController, ArduinoTemperatureControllerParams, ArduinoTemperatureControllerPortParams, ArduinoTemperatureControllerPoolParams

abstract type ArduinoTemperatureControllerParams <: DeviceParams end

Base.@kwdef struct ArduinoTemperatureControllerPortParams <: ArduinoTemperatureControllerParams
  # Control
  
  mode::TemperatureControlMode 
  # TODO Add remaining parameter for control, for optional make it like
  # thresholds::Union{Vector{Integer}, Nothing} = nothing
  # Channel
  targetTemps::Vector{Integer}
  maxTemps::Vector{Integer}

  # Communication
  portAddress::String
  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoTemperatureControllerPortParams(dict::Dict) = params_from_dict(ArduinoTemperatureControllerPortParams, dict)

Base.@kwdef struct ArduinoTemperatureControllerPoolParams <: ArduinoTemperatureControllerParams
  # Control
  mode::TemperatureControlMode 
  targetTemps::Vector{Integer}
  maxTemps::Vector{Integer}
  # Communication
  description::String
  @add_serial_device_fields '#'
  @add_arduino_fields "!" "*"
end
ArduinoTemperatureControllerPoolParams(dict::Dict) = params_from_dict(ArduinoTemperatureControllerPoolParams, dict)

Base.@kwdef mutable struct ArduinoTemperatureController <: TemperatureController
  @add_device_fields ArduinoTemperatureControllerParams
  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end

neededDependencies(::ArduinoTemperatureController) = []
optionalDependencies(::ArduinoTemperatureController) = [SerialPortPool]

function _init(controller::ArduinoTemperatureController)
  params = controller.params
  sd = initSerialDevice(controller, params)
  @info "Connection to ArduinoTemperatureController established."        
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, sd = sd)
  controller.ard = ard
  setMaximumTemps(controller, params.maxTemps)
  setTargetTemps(controller, params.targetTemps)
  controlMode(controller, params.mode)
  # TODO Configure targetTemps, controlMode and control parameters
end

function initSerialDevice(controller::ArduinoTemperatureController, params::ArduinoTemperatureControllerPortParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(controller, sd)
  return sd
end

function initSerialDevice(controller::ArduinoTemperatureController, params::ArduinoTemperatureControllerPoolParams)
  sd = initSerialDevice(controller, params.description)
  checkSerialDevice(controller, sd)
  return sd
end

function checkSerialDevice(controller::ArduinoTemperatureController, sd::SerialDevice)
  try
    reply = query(sd, "!VERSION*")
    if !(startswith(reply, "HEATINGUNIT:1"))
        close(sd)
        throw(ScannerConfigurationError(string("Connected to wrong Device ", reply)))
    end
    return sd
  catch e
    throw(ScannerConfigurationError("Could not verify if connected to correct device"))
  end
end

function numChannels(controller::ArduinoTemperatureController)
  return length(controller.params.selectSensors)
end

function getChannelNames(controller::ArduinoTemperatureController)
  if length(controller.params.selectSensors) == length(controller.params.nameSensors) #This should be detected during construction
    return controller.params.nameSensors[controller.params.selectSensors]
  else 
    return []
  end
end

function getChannelGroups(controller::ArduinoTemperatureController)
  return controller.params.groupSensors[controller.params.selectSensors]
end

function getTemperatures(controller::ArduinoTemperatureController; names::Bool=false)
  temp = retrieveTemps(controller)
  if length(temp) == controller.params.numSensors
      if names
          return [temp[controller.params.selectSensors] controller.params.nameSensors[controller.params.selectSensors]]
      else
          return temp[controller.params.selectSensors]
      end
  else
      return zeros(length(controller.params.selectSensors))
  end
end

function getTemperature(controller::ArduinoTemperatureController, channel::Int)
  temp = retrieveTemps(controller, "GET:ALLTEMPS")
  return temp[channel]
end

function retrieveTemps(controller::ArduinoTemperatureController, query::AbstractString = "GET:ALLTEMPS")
  TempDelim = "," 
  # TODO Retrieve temp properly
  Temps = sendCommand(controller.ard, query)
  result =  tryparse.(Float64,split(Temps,TempDelim))
  result = map(x -> isnothing(x) ? 0.0 : x, result)
  return result
end


function setMaximumTemps(controller::ArduinoTemperatureController, maxTemps::Array)
    if length(maxTemps) == controller.params.numSensors
        maxTempString= join(maxTemps, ",")
        ack = sendCommand(controller.ard, "SET:TMAX:<"*maxTempString*">")
        if ack
          @info "Set max temp for ArduinoTemperatureController $(id(controller))."
          return true
        else
          @warn "Could not set max temp for ArduinoTemperatureController $(id(controller))."
        end
    else
        @warn "Please parse a maximum temperature for each controller" controller.params.numSensors
    end
    return false
end

function getMaximumTemps(controller::ArduinoTemperatureController)
  temp = retrieveTemps(controller, "GET:TMAX")
  return temp[channel]
end

close(controller::ArduinoTemperatureController) = close(controller.ard)





export setTargetTemps
function setTargetTemps(controller::ArduinoTemperatureController, targetTemps::Vector{Integer})
  if length(targetTemps) == controller.params.numSensors
    targetTempString= join(targetTemps, ",")
    ack = sendCommand(controller.ard, "SET:TSET:<"*targetTempString*">")
    if ack
      @info "Set target temp for ArduinoTemperatureController $(id(controller))."
      return true
    else
      @warn "Could not set target temp for ArduinoTemperatureController $(id(controller))."
    end
  else
    @warn "Please parse a maximum temperature for each controller" controller.params.numSensors
  end
  return false
end


function getTargetTemps(controller::ArduinoTemperatureController)
  temp = retrieveTemps(controller, "GET:TSET")
  return temp[channel]
end

# mode is always for ALL 
function setControlMode(controller::ArduinoTemperatureController, mode::TemperatureControlMode)
  cmd = ""
  if mode == TEMP_THRESHOLD
    cmd = "SET:C:THRES"
  elseif mode == TEMP_PID
    cmd = "SET:C:PWM"
  else
    throw(ScannerConfigurationError("Temp Controller does not support mode $mode"))
  end
  return sendCommand(controller.ard, cmd)
end

#function getControlMode(controller::ArduinoTemperatureController)
#  # TODO
#end

# TODO This would be your AC enable
function enableControl(controller::ArduinoTemperatureController)
  return sendCommand(controller.ard, "SET:ENABLE_HEATING:<1>")
end

function disableControl(controller::ArduinoTemperatureController)
  return sendCommand(controller.ard, "SET:ENABLE_HEATING:<0>")
end