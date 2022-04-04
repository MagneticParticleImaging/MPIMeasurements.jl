export ArduinoTemperatureSensor, ArduinoTemperatureSensorParams
# TODO comment relevant Arduino code once added to project
Base.@kwdef struct ArduinoTemperatureSensorParams <: DeviceParams
  portAdress::String
  numSensors::Int
  maxTemps::Vector{Int}
  selectSensors::Vector{Int}
  nameSensors::Vector{String}

  commandStart::String = "!"
  commandEnd::String = "*"
  pause_ms::Int = 30
  timeout_ms::Int = 1000
  delim::String = "#"
  baudrate::Integer = 115200
  ndatabits::Integer = 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1
end
ArduinoTemperatureSensorParams(dict::Dict) = params_from_dict(ArduinoTemperatureSensorParams, dict)

Base.@kwdef mutable struct ArduinoTemperatureSensor <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::ArduinoTemperatureSensorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String,Union{Device,Missing}}

  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end

neededDependencies(::ArduinoTemperatureSensor) = []
optionalDependencies(::ArduinoTemperatureSensor) = []

function _init(sensor::ArduinoTemperatureSensor)
  params = sensor.params
  spTU = SerialPort(params.portAdress)
  open(spTU)
  set_speed(spTU, params.baudrate)
  set_frame(spTU,ndatabits=params.ndatabits,parity=params.parity,nstopbits=params.nstopbits)
  #set_flow_control(spTU,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
  sleep(2) # TODO why this sleep?
  flush(spTU)
  write(spTU, "!VERSION*#")
  response=readuntil(spTU, Vector{Char}(params.delim), params.timeout_ms);
  @info response
  if(!(response == "TEMPBOX:3") ) 
      close(spTU)
      throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
    else
      @info "Connection to ArduinoTempBox established."        
  end

  sd = SerialDevice(spTU, params.pause_ms, params.timeout_ms, params.delim, params.delim)
  ard = SimpleArduino(;commandStart = params.commandStart, commandEnd = params.commandEnd, delim = params.delim, sd = sd)
  sensor.ard = ard
  setMaximumTemps(sensor, params.maxTemps)
end

function numChannels(sensor::ArduinoTemperatureSensor)
  return length(sensor.params.selectSensors)
end

function getChannelNames(sensor::ArduinoTemperatureSensor)
  if length(sensor.params.selectSensors) == length(sensor.params.nameSensors)
    return sensor.params.nameSensors[sensor.params.selectSensors]
  else 
    return []
  end
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
