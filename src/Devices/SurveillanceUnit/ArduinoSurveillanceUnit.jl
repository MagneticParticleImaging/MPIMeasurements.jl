export ArduinoSurveillanceUnit

Base.@kwdef struct ArduinoSurveillanceUnitParams <: DeviceParams
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

ArduinoSurveillanceUnitParams(dict::Dict) = params_from_dict(ArduinoSurveillanceUnitParams, dict)
Base.@kwdef mutable struct ArduinoSurveillanceUnit <: SurveillanceUnit
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::IselRobotParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String,Union{Device,Missing}}

  sd::Union{SerialDevice, Nothing} = nothing
end


neededDependencies(::ArduinoSurveillanceUnit) = []
optionalDependencies(::ArduinoSurveillanceUnit) = []

Base.close(su::ArduinoSurveillanceUnit) = close(su.sd.sp)

function init(su::ArduinoSurveillanceUnit)
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
  else    
    throw(ScannerConfigurationError(string("Connected to wrong Device", response)))
  end
end

# WTF?
function CheckACQ(Arduino::ArduinoSurveillanceUnit, ACQ)
  if ACQ == "ACQ"
    @info "Command Received"
    return ACQ;
  else
    @warn "Error, Unknown response" ACQ
  end
end


function ArduinoCommand(Arduino::ArduinoSurveillanceUnit, cmd::String)
  cmd = Arduino.CommandStart * cmd * Arduino.CommandEnd * Arduino.delim;
  return query(Arduino.sd, cmd);
end

function ArEnableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "ENABLE:WD")
  CheckACQ(Arduino, ACQ)
end

function ArDisableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "DISABLE:WD")
  CheckACQ(Arduino, ACQ)
end

function getTemperatures(Arduino::ArduinoSurveillanceUnit) # toDo: deprecated
  Temps = ArduinoCommand(Arduino, "GET:TEMP")
  TempDelim = "T"

  temp =  tryparse.(Float64, split(Temps, TempDelim))

  # We hardcode this to four here
  tempFloat = zeros(4)

  for i = 1:min(length(tempFloat), length(temp)) 
    if temp[i] != nothing
        tempFloat[i] = temp[i]
    end
  end

  return tempFloat
end

function GetDigital(Arduino::ArduinoSurveillanceUnit, DIO::Int)
  DIO = ArduinoCommand(Arduino, "GET:DIGITAL:" * string(DIO))
  return DIO;
end
function GetAnalog(Arduino::ArduinoSurveillanceUnit, ADC::Int)
  ADC = ArduinoCommand(Arduino, "GET:ANALOG:A" * string(ADC))
  return ADC;
end

function parsebool(s::Char)
  if s == '1'
    return true
  elseif s == '0'
    return false
  else
    throw(DomainError(s))
  end
end

function GetErrorStatus(Arduino::ArduinoSurveillanceUnit)
  Errorcode = ArduinoCommand(Arduino, "GET:STATUS");
  ErrorcodeBool = [parsebool(x) for x in Errorcode]
  return ErrorcodeBool
end

function ResetWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "RESET:WD")
  CheckACQ(Arduino, ACQ)
end

function EnableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "ENABLE:WD")
  CheckACQ(Arduino, ACQ)
end

function DisableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "DISABLE:WD")
  CheckACQ(Arduino, ACQ)
end

function ResetFail(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "RESET:FAIL")
  CheckACQ(Arduino, ACQ)
end

function DisableSurveillance(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "DISABLE:SURVEILLANCE")
  CheckACQ(Arduino, ACQ)
end

function EnableSurveillance(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "ENABLE:SURVEILLANCE")
  CheckACQ(Arduino, ACQ)
end

function GetCycletime(Arduino::ArduinoSurveillanceUnit)
  tcycle = ArduinoCommand(Arduino, "GET:CYCLETIME")
  return tcycle;
end

function ResetArduino(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "RESET:ARDUINO")
  CheckACQ(Arduino, ACQ)
end

function enableACPower(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "ENABLE:AC");
  CheckACQ(Arduino, ACQ)
  sleep(0.5)
end

function disableACPower(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "DISABLE:AC");
  CheckACQ(Arduino, ACQ)
end

function NOTAUS(Arduino::ArduinoSurveillanceUnit)
  ACQ = ArduinoCommand(Arduino, "NOTAUS");
  CheckACQ(Arduino, ACQ)
end
