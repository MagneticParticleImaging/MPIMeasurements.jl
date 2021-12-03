export ArduinoSurveillanceUnitInternalTemp, ArduinoSurveillanceUnitInternalTempParams

Base.@kwdef struct ArduinoSurveillanceUnitInternalTempParams <: DeviceParams
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

ArduinoSurveillanceUnitInternalTempParams(dict::Dict) = params_from_dict(ArduinoSurveillanceUnitInternalTempParams, dict)
Base.@kwdef mutable struct ArduinoSurveillanceUnitInternalTemp <: ArduinoSurveillanceUnit
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::ArduinoSurveillanceUnitInternalTempParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String,Union{Device,Missing}}

  ard::Union{SimpleArduino, Nothing} = nothing # Use composition as multiple inheritance is not supported
end


neededDependencies(::ArduinoSurveillanceUnitInternalTemp) = []
optionalDependencies(::ArduinoSurveillanceUnitInternalTemp) = []

function init(su::ArduinoSurveillanceUnitInternalTemp)
  @info "Initializing ArduinoSurveillanceUnit with ID $(su.deviceID)"
  sp = SerialPort(su.params.portAdress)
  open(sp)
	set_speed(sp, su.params.baudrate)
	set_frame(sp, ndatabits=su.params.ndatabits, parity=su.params.parity, nstopbits=su.params.nstopbits)
	# set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
  sleep(2)
  flush(sp)
  write(sp, "!ConnectionEstablished*#")
  response = readuntil(sp, Vector{Char}(su.params.delim), su.params.timeout_ms);
  @info response
  if (response == "ArduinoSurveillanceV1" || response == "ArduinoSurveillanceV2"  )
    @info "Connection to ArduinoSurveillanceUnit established"
    su.sd = SerialDevice(sp, su.params.pause_ms, su.params.timeout_ms, su.params.delim, su.params.delim)
    su.ard = SimpleArduino(;commandStart = su.params.commandStart, commandEnd = su.params.commandEnd, delim = su.params.delim, sd = sd)
  else    
    throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
  end
  su.present = true
end

sendCommand(su::ArduinoSurveillanceUnitInternalTemp, cmdString::String) = sendCommand(su.ard, cmdString) 

function getTemperatures(Arduino::ArduinoSurveillanceUnitInternalTemp) # toDo: deprecated
  Temps = sendCommand(Arduino, "GET:TEMP")
  TempDelim = "T"

  temp =  tryparse.(Float64, split(Temps, TempDelim))

  # We hardcode this to four here
  tempFloat = zeros(4)

  for i = 1:min(length(tempFloat), length(temp)) 
    if temp[i] !== nothing
        tempFloat[i] = temp[i]
    end
  end

  return tempFloat
end