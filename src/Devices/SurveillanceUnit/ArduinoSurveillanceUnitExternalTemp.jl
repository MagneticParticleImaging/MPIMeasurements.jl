export ArduinoSurveillanceUnitExternalTemp, ArduinoSurveillanceUnitExternalTempParams

Base.@kwdef struct ArduinoSurveillanceUnitExternalTempParams <: DeviceParams
  portAdress::String
  commandStart::String = "!"
  commandEnd::String = "*"

  pause_ms::Int = 30
  timeout_ms::Int = 500
  delim::String = "#"
  baudrate::Integer = 9600
  ndatabits::Integer = 8
  parity::SPParity = SP_PARITY_NONE
  nstopbits::Integer = 1
end

ArduinoSurveillanceUnitExternalTempParams(dict::Dict) = params_from_dict(ArduinoSurveillanceUnitExternalTempParams, dict)
Base.@kwdef mutable struct ArduinoSurveillanceUnitExternalTemp <: ArduinoSurveillanceUnit
  @add_device_fields ArduinoSurveillanceUnitExternalTempParams

  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end

Base.close(su::ArduinoSurveillanceUnitExternalTemp) = close(su.ard)

sendCommand(su::ArduinoSurveillanceUnitExternalTemp, cmdString::String) = sendCommand(su.ard, cmdString) 

neededDependencies(::ArduinoSurveillanceUnitExternalTemp) = [ArduinoTemperatureSensor] # could in theory be generic temp sensor
optionalDependencies(::ArduinoSurveillanceUnitExternalTemp) = []

function _init(su::ArduinoSurveillanceUnitExternalTemp)
  sp = SerialPort(su.params.portAdress)
  open(sp)
	set_speed(sp, su.params.baudrate)
	set_frame(sp, ndatabits=su.params.ndatabits, parity=su.params.parity, nstopbits=su.params.nstopbits)
	# set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
  sleep(2)
  flush(sp)
  write(sp, "!VERSION*#")
  response = readuntil(sp, Vector{Char}(su.params.delim), su.params.timeout_ms);
  @info response
  if (response == "SURVBOX:3#")
    @info "Connection to ArduinoSurveillanceUnit established"
    sd = SerialDevice(sp, su.params.pause_ms, su.params.timeout_ms, su.params.delim, su.params.delim)
    su.ard = SimpleArduino(;commandStart = su.params.commandStart, commandEnd = su.params.commandEnd, delim = "", sd = sd)
  else    
    throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
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