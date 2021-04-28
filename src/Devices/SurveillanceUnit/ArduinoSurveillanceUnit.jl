export ArduinoSurveillanceUnit

struct ArduinoSurveillanceUnit <: SurveillanceUnit
  sd::SerialDevice
  CommandStart::String
  CommandEnd::String
  delim::String
end

Base.close(su::ArduinoSurveillanceUnit) = close(su.sd.sp)

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
    response=readuntil(sp, Vector{Char}(delim_read), timeout_ms);
    @info response
    if(response == "ArduinoSurveillanceV1" || response == "ArduinoSurveillanceV2"  )
        @info "Connection to ArduinoSurveillanceUnit established"
        return ArduinoSurveillanceUnit(SerialDevice(sp,pause_ms, timeout_ms, delim_read, delim_write),CommandStart,CommandEnd,delim)
    else    
        @warn "Connected to wrong Device" response
        return sp;
    end
end

# WTF?
function CheckACQ(Arduino::ArduinoSurveillanceUnit,ACQ)
    if ACQ=="ACQ"
        @info "Command Received"
        return ACQ;
    else
        @warn "Error, Unknown response" ACQ
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

function getTemperatures(Arduino::ArduinoSurveillanceUnit) #toDo: deprecated
    Temps = ArduinoCommand(Arduino, "GET:TEMP")
    TempDelim = "T"

    temp =  tryparse.(Float64,split(Temps,TempDelim))

    # We hardcode this to four here
    tempFloat = zeros(4)

    for i=1:min(length(tempFloat),length(temp)) 
      if temp[i] != nothing
          tempFloat[i] = temp[i]
      end
    end

    return tempFloat
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

function enableACPower(Arduino::ArduinoSurveillanceUnit, scanner::MPIScanner)
    ACQ=ArduinoCommand(Arduino,"ENABLE:AC");
    CheckACQ(Arduino,ACQ)
    sleep(0.5)
end

function disableACPower(Arduino::ArduinoSurveillanceUnit, scanner::MPIScanner)
    ACQ=ArduinoCommand(Arduino,"DISABLE:AC");
    CheckACQ(Arduino,ACQ)
end

function NOTAUS(Arduino::ArduinoSurveillanceUnit)
    ACQ=ArduinoCommand(Arduino,"NOTAUS");
    CheckACQ(Arduino,ACQ)
end
