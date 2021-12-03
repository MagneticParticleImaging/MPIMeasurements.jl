export ArduinoWithExternalTempUnit, getStatus, resetDAQ
# TODO comment relevant Arduino code once added to project
struct ArduinoWithExternalTempUnit <: SurveillanceUnit
  sd::Vector{SerialDevice}
  CommandStart::String
  CommandEnd::String
  delim::String
  numSensors::Number
  maxTemps::Array
  selectSensors::Array
  nameSensors::Array
end

function Base.close(su::ArduinoWithExternalTempUnit)
  for s in su.sd
    close(s.sp)
  end
end

#init from SurveillanceUnit.jl
function ArduinoWithExternalTempUnit(params::Dict) 
  # Here we could put more parameters into the TOML file
  su = ArduinoWithExternalTempUnit(params["connection"],
                                   params["numSensors"],
                                   params["maxTemps"],  
                                   params["selectSensors"],
                                   params["nameSensors"])
  setMaximumTemps(su, params["maxTemps"])
  return su
end


function ArduinoWithExternalTempUnit(portAdress::Vector{T}, numSensors::Number, maxTemps::Array, selectSensors::Array, nameSensors::Array) where T <: AbstractString
    # general parameters
    pause_ms::Int=30
    timeout_ms = [500, 1000]
    delim::String="#"
    delim_read::String="#"
    delim_write::String="#"
    baudrate = [9600, 115200]
    CommandStart="!"
    CommandEnd="*"
    ndatabits::Integer=8
    parity::SPParity=SP_PARITY_NONE
    nstopbits::Integer=1

    ### build SU arduino ###
    spSU = SerialPort(portAdress[1])
    open(spSU)
	set_speed(spSU, baudrate[1])
	set_frame(spSU,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	#set_flow_control(spSU,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
    sleep(2)
    flush(spSU)
    write(spSU, "!ConnectionEstablished*#")
    response=readuntil(spSU, Vector{Char}(delim_read), timeout_ms[1]);
    @info response
    if(!(response == "ArduinoSurveillanceV1" || response == "ArduinoSurveillanceV2") ) 
        close(spSU)
        @error "Connected to wrong Device: SU" response portAdress[1]
    else
        @info "Connection to ArduinoSU established."        
    end

    ### build Temp arduino ###
    spTU = SerialPort(portAdress[2])
    open(spTU)
	set_speed(spTU, baudrate[2])
	set_frame(spTU,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	#set_flow_control(spTU,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
    sleep(2) 
    flush(spTU)
    write(spTU, "!ConnectionEstablished*#")
    response=readuntil(spTU, Vector{Char}(delim_read), timeout_ms[2]);
    @info response
    if(!(response == "ArduinoTemperatureUnitV2") ) 
        close(spTU)
        @error "Connected to wrong Device: TU" response portAdress[2]
    else
        @info "Connection to ArduinoTU established."        
    end

    sds = [SerialDevice(spSU, pause_ms, timeout_ms[1], delim_read, delim_write), 
           SerialDevice(spTU, pause_ms, timeout_ms[2], delim_read, delim_write)]

    sp = ArduinoWithExternalTempUnit(sds, CommandStart, CommandEnd, delim, numSensors, maxTemps, selectSensors, nameSensors)

    return sp;
end


### general command structure
function ArduinoCommand(Arduino::ArduinoWithExternalTempUnit, cmd::String, id::Int)
    cmd=Arduino.CommandStart*cmd*Arduino.CommandEnd*Arduino.delim;
    return query(Arduino.sd[id],cmd);
end


###############################################
#----------- Temperature Unit ---------- "id=2"

function getTemperatures(Arduino::ArduinoWithExternalTempUnit; names::Bool=false)
    TempDelim = "," 
    
    Temps = ArduinoCommand(Arduino, "GET:ALLTEMPS", 2)
    Temps = Temps[7:end]  #filter out "TEMPS:" at beginning of answer

    #@info Temps now() 
    temp =  tryparse.(Float64,split(Temps,TempDelim))

    if length(temp) == Arduino.numSensors
        tempFloat = zeros(length(temp)) 
        for i=1:min(length(tempFloat),length(temp)) 
            if temp[i] != nothing
                tempFloat[i] = temp[i]
            end
        end

        if names
            return [tempFloat[Arduino.selectSensors] Arduino.nameSensors[Arduino.selectSensors]]
        else
            return tempFloat[Arduino.selectSensors]
        end
    else
        return zeros(length(Arduino.selectSensors))
    end
end

export showCommands
function showCommands(Arduino::ArduinoWithExternalTempUnit)
    print(ArduinoCommand(Arduino, "GET:COMMANDS", 2))
end

export setMaximumTemps
function setMaximumTemps(Arduino::ArduinoWithExternalTempUnit, maxTemps::Array)
    if length(maxTemps) == Arduino.numSensors
        maxTempString=""
        for i in 1:Arduino.numSensors
            if i != Arduino.numSensors
                maxTempString *= string(maxTemps[i])*","
            else
                maxTempString *= string(maxTemps[i])
            end
        end
        ack = ArduinoCommand(Arduino, "SET:MAXTEMPS:<"*maxTempString*">", 2)
        @info "acknowledge of MaxTemps from TempUnit."
    else
        @warn "Please parse a maximum temperature for each sensor" Arduino.numSensors
    end
end

export getMaximumTemps
function getMaximumTemps(Arduino::ArduinoWithExternalTempUnit)
    println(ArduinoCommand(Arduino, "GET:MAXTEMPS", 2))
end


export CheckACQ
function CheckACQ(Arduino::ArduinoWithExternalTempUnit,ACQ)
    if ACQ=="ACQ"
        @info "Command Received"
        return ACQ;
    else
        @warn "Error, Unknown response" ACQ
    end
end

function GetStatus(Arduino::ArduinoWithExternalTempUnit)
    status = ArduinoCommand(Arduino,"GET:STATS", 1)
    return status
end

function resetDAQ(Arduino::ArduinoWithExternalTempUnit)
    ACQ = ArduinoCommand(Arduino,"RESET:RP", 1)
    CheckACQ(Arduino,ACQ)
end
 
hasResetDAQ(su::ArduinoWithExternalTempUnit) = true