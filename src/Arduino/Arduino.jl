#using SerialPorts
export ArduinoSurveillanceUnit

struct ArduinoSurveillanceUnit <: Arduino
  sd::SerialDevice
  CommandStart::String
end


function ArduinoSurveillanceUnit(portAdress::AbstractString)
    pause_ms::Int=30
    timeout_ms::Int=500
    delim_read::String="#"
    delim_write::String="#"
    baudrate::Integer = 9600
    CommandStart="!"
    sp = SerialPort(portAdress)
    flush(sp)
    write(sp, "ConnectionEstablished$delim_write")
    if(readuntil(sp, delim_read, timeout_ms) == "ArduinoSurveillanceV1$delim_read")
            println("Connected to ArduinoSurveillanceUnit")
            return ArduinoSurveillanceUnit(sp,pause_ms, timeout_ms, delim_read, delim_write),CommandStart)
    else
            println("Connected to WrongDevice")
    end
end


function CheckACQ(ACQ)
    if ACQ=="AQQ" 
        println("Command Received");
        return ACQ;
    else
            println("Error, Unknown response $ACQ")
    end
end


 function ArduinoCommand(Arduino::ArduinoSurveillanceUnit, cmd::String)
    return query(Arduino,cmd);
end
 
function ArEnableWatchDog(Arduino::ArduinoSurveillanceUnit)
   ACQ= ArduinoCommand(Arduino, Arduino.CommandStart*"ENABLE:WD")
   CheckACQ(ACQ)
end

function ArDisableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ= ArduinoCommand(Arduino, Arduino.CommandStart*"DISABLE:WD")
    CheckACQ(ACQ)
end

function GetTemperatures(Arduino::ArduinoSurveillanceUnit)
    Temp=ArduinoCommand(Arduino, Arduino.CommandStart*"GET:TEMP");
    TempDelim="/n";
    return split(Temps,TempDelim);
end

function GetDigital(Arduino::ArduinoSurveillanceUnit, DIO::Int)
    DIO=ArduinoCommand(Arduino,Arduino.CommandStart*"GET:DIGITAL:"*Sting(DIO))
    return DIO;
end
function GetAnalog(Arduino::ArduinoSurveillanceUnit, ADC::Int)
    ADC=ArduinoCommand(Arduino,Arduino.CommandStart*"GET:DIGITAL:A"*Sting(ADC))
    return ADC;
end

function parsebool(s::Char)
    if s == '1'
        return true
    elseif s=='0'
        return false
    else
        throw(DomainError())
    end
end

function GetStaus(Arduino::ArduinoSurveillanceUnit)
    Errorcode=ArduinoCommand(Arduino,Arduino.CommandStart*"GET:STATUS");
    ErrorcodeBool=[parsebool(x) for x in Errorcode]
    return ErrorcodeBool
end

function ResetWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"RESET:WD")
    CheckACQ(ACQ)
end

function EnableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"ENABLE:WD")
    CheckACQ(ACQ)
end

function DisableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"DISABLE:WD")
    CheckACQ(ACQ)
end

function ResetFail(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"RESET:FAIL")
    CheckACQ(ACQ)
end

function DisableSurveillance(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"DISABLE:SURVEILLANCE")
    CheckACQ(ACQ)
end

function EnableSurveillance(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"ENABLE:SURVEILLANCE")
    CheckACQ(ACQ)
end

function GetCycletime(Arduino::ArduinoSurveillanceUnit)
    tcycle=ArduinoCommand(Arduino,Arduino.CommandStart*"GET:CYCLETIME")
    return tcycle;
end

function ResetArduino(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,Arduino.CommandStart*"RESET:ARDUINO")
    CheckACQ(ACQ)
end