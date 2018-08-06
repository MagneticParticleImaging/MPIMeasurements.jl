export ArduinoSurveillanceUnit

struct ArduinoSurveillanceUnit <: SurveillanceUnit
  sd::SerialDevice
  CommandStart::String
  CommandEnd::String
  delim::String
end

function ArduinoSurveillanceUnit(params::Dict)
  # Here we could put more parameters into the TOML file
  su = ArduinoSurveillanceUnit(params["connection"])
 # DisableWatchDog(su)
  #DisableSurveillance(su)
  return su
end


function ArduinoSurveillanceUnit(portAdress::AbstractString)
    pause_ms::Int=30
    timeout_ms::Int=500
    delim::String="#"
    delim_read::String="#"
    delim_write::String="#"
    baudrate::Integer = 9600
    CommandStart="!"
    CommandEnd="*"
    ndatabits::Integer=8
    parity::SPParity=SP_PARITY_NONE
    nstopbits::Integer=1
    sp = SerialPort(portAdress)
    open(sp)
	set_speed(sp, baudrate)
	set_frame(sp,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	#set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
    sleep(2)
    flush(sp)
    write(sp, "!ConnectionEstablished*#")
    response=readuntil(sp, delim_read, timeout_ms);
    if(response == "ArduinoSurveillanceV1")
            println("Connected to ArduinoSurveillanceUnit")
            return ArduinoSurveillanceUnit(SerialDevice(sp,pause_ms, timeout_ms, delim_read, delim_write),CommandStart,CommandEnd,delim)
    else
            println("Connected to WrongDevice")
            println("$response")
            return sp;
    end
end


function CheckACQ(Arduino,ACQ)
    if ACQ=="ACQ"
        println("Command Received");
        return ACQ;
    else
            println("Error, Unknown response $ACQ")
    end
end


 function ArduinoCommand(Arduino::ArduinoSurveillanceUnit, cmd::String)
     cmd=Arduino.CommandStart*cmd*Arduino.CommandEnd*Arduino.delim;
    return query(Arduino.sd,cmd);
end

function ArEnableWatchDog(Arduino::ArduinoSurveillanceUnit)
   ACQ= ArduinoCommand(Arduino, "ENABLE:WD")
   CheckACQ(Arduino,ACQ)
end

function ArDisableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ= ArduinoCommand(Arduino, "DISABLE:WD")
    CheckACQ(Arduino,ACQ)
end

function getTemperatures(Arduino::ArduinoSurveillanceUnit)
    Temps=ArduinoCommand(Arduino, "GET:TEMP")
    TempDelim="T"

    temp =  tryparse.(Float64,split(Temps,TempDelim))

    tempFloat = []

    for t in temp
      if !isnull(t)
          push!(tempFloat, get(t))
      end
    end

    if length(tempFloat) == 0
      return [0.0]
    else
      return tempFloat
    end
end

function GetDigital(Arduino::ArduinoSurveillanceUnit, DIO::Int)
    DIO=ArduinoCommand(Arduino,"GET:DIGITAL:"*string(DIO))
    return DIO;
end
function GetAnalog(Arduino::ArduinoSurveillanceUnit, ADC::Int)
    ADC=ArduinoCommand(Arduino,"GET:ANALOG:A"*string(ADC))
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

function GetErrorStatus(Arduino::ArduinoSurveillanceUnit)
    Errorcode=ArduinoCommand(Arduino,"GET:STATUS");
    ErrorcodeBool=[parsebool(x) for x in Errorcode]
    return ErrorcodeBool
end

function ResetWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"RESET:WD")
    CheckACQ(Arduino,ACQ)
end

function EnableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"ENABLE:WD")
    CheckACQ(Arduino,ACQ)
end

function DisableWatchDog(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"DISABLE:WD")
    CheckACQ(Arduino,ACQ)
end

function ResetFail(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"RESET:FAIL")
    CheckACQ(Arduino,ACQ)
end

function DisableSurveillance(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"DISABLE:SURVEILLANCE")
    CheckACQ(Arduino,ACQ)
end

function EnableSurveillance(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"ENABLE:SURVEILLANCE")
    CheckACQ(Arduino,ACQ)
end

function GetCycletime(Arduino::ArduinoSurveillanceUnit)
    tcycle=ArduinoCommand(Arduino,"GET:CYCLETIME")
    return tcycle;
end

function ResetArduino(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"RESET:ARDUINO")
    CheckACQ(Arduino,ACQ)
end

function enableACPower(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"ENABLE:AC");
    CheckACQ(Arduino,ACQ)
end

function disableACPower(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"DISABLE:AC");
    CheckACQ(Arduino,ACQ)
end

function NOTAUS(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"NOTAUS");
    CheckACQ(Arduino,ACQ)
end
