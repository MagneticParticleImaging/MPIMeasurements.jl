export ArduinoSurveillanceUnit
export arEnableWatchDog, arDisableWatchDog, getTemperatures
export getDigital, getAnalog, getErrorStatus, resetWatchDog, enableWatchDog
export disableWatchDog, resetFail, disableSurveillance, enableSurveillance
export getCycletime, resetArduino, enableACPower, disableACPower, NOTAUS

abstract type ArduinoSurveillanceUnit <: SurveillanceUnit end

# TODO maybe return true if command was Received
# Should ACQ be ACK?
function checkACQ(ard::ArduinoSurveillanceUnit, reply)
  if reply == "ACQ"
    @info "Command Received"
    return reply;
  else
    @warn "Error, Unknown response" reply
  end
end

function parseBool(ard::ArduinoSurveillanceUnit, s::Char)
  if s == '1'
    return true
  elseif s == '0'
    return false
  else
    throw(DomainError(s))
  end
end

function arEnableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "ENABLE:WD")
  checkACQ(Arduino, ACQ)
end

function arDisableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "DISABLE:WD")
  checkACQ(Arduino, ACQ)
end

function getDigital(Arduino::ArduinoSurveillanceUnit, DIO::Int)
  DIO = sendCommand(Arduino, "GET:DIGITAL:" * string(DIO))
  return DIO;
end
function getAnalog(Arduino::ArduinoSurveillanceUnit, ADC::Int)
  ADC = sendCommand(Arduino, "GET:ANALOG:A" * string(ADC))
  return ADC;
end

function getErrorStatus(Arduino::ArduinoSurveillanceUnit)
  Errorcode = sendCommand(Arduino, "GET:STATUS");
  ErrorcodeBool = [parseBool(Arduino, x) for x in Errorcode]
  return ErrorcodeBool
end

function resetWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "RESET:WD")
  checkACQ(Arduino, ACQ)
end

function enableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "ENABLE:WD")
  checkACQ(Arduino, ACQ)
end

function disableWatchDog(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "DISABLE:WD")
  checkACQ(Arduino, ACQ)
end

function resetFail(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "RESET:FAIL")
  checkACQ(Arduino, ACQ)
end

function disableSurveillance(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "DISABLE:SURVEILLANCE")
  checkACQ(Arduino, ACQ)
end

function enableSurveillance(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "ENABLE:SURVEILLANCE")
  checkACQ(Arduino, ACQ)
end

function getCycletime(Arduino::ArduinoSurveillanceUnit)
  tcycle = sendCommand(Arduino, "GET:CYCLETIME")
  return tcycle;
end

function resetArduino(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "RESET:ARDUINO")
  checkACQ(Arduino, ACQ)
end

function enableACPower(Arduino::ArduinoSurveillanceUnit)
  reply = sendCommand(Arduino, "ENABLE:AC");
  if !parse(Bool, reply)
    error("AC could not be enabled. Check SU fail")
  end
end

function disableACPower(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "DISABLE:AC");
  checkACQ(Arduino, ACQ)
end

function enableHeating(ard::ArduinoSurveillanceUnit)
  ACQ = sendCommand(ard, "ENABLE:HEATING");
  checkACQ(Arduino, ACQ)
end

function disableHeating(ard::ArduinoSurveillanceUnit)
  ACQ = sendCommand(ard, "DISABLE:HEATING");
  checkACQ(Arduino, ACQ)
end

# TODO this does not seem to be implemented in external client, check server code
function NOTAUS(Arduino::ArduinoSurveillanceUnit)
  ACQ = sendCommand(Arduino, "NOTAUS");
  checkACQ(Arduino, ACQ)
end
