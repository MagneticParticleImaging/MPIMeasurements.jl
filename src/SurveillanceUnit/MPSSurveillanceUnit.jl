export MPSSurveillanceUnit

struct MPSSurveillanceUnit <: SurveillanceUnit
  sd::SerialDevice
  CommandStart::String
  CommandEnd::String
  delim::String
end

Base.close(su::MPSSurveillanceUnit) = close(su.sd.sp)

function MPSSurveillanceUnit(params::Dict)
  # Here we could put more parameters into the TOML file
  su = MPSSurveillanceUnit(params["connection"])
 # DisableWatchDog(su)
  #DisableSurveillance(su)
  return su
end

function ArduinoCommand(Arduino::MPSSurveillanceUnit, cmd::String)
    cmd=Arduino.CommandStart*cmd*Arduino.CommandEnd*Arduino.delim;
   return query(Arduino.sd,cmd);
end

function MPSSurveillanceUnit(portAdress::AbstractString)
    pause_ms::Int=30
    timeout_ms::Int=500
    delim::String="#"
    delim_read::String="#"
    delim_write::String="#"
    baudrate::Integer = 115200
    CommandStart="!"
    CommandEnd="*"
    ndatabits::Integer=8
    parity::SPParity=SP_PARITY_NONE
    nstopbits::Integer=1
    sp = SerialPort(resolvedSymlink(portAdress))
    open(sp)
	set_speed(sp, baudrate)
	set_frame(sp,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	#set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
    sleep(2)
    flush(sp)
    write(sp, "!ConnectionEstablished*#")
    response = readuntil(sp, Vector{Char}(delim_read), timeout_ms);
    @show response
    if(response == "MPSSurveillanceV1")
            @info "Connection to MPSSurveillanceUnit established"
            return MPSSurveillanceUnit(SerialDevice(sp,pause_ms, timeout_ms, delim_read, delim_write),CommandStart,CommandEnd,delim)
    else
            @warn "Connected to wrong Device" response
            return nothing;
    end
end

function getTemperatures(Arduino::MPSSurveillanceUnit)
    Temps=ArduinoCommand(Arduino, "GET:TEMP")
    #@info Temps
    TempDelim="T"

    temp =  tryparse.(Float64,split(Temps,TempDelim))

    tempFloat = []

    for t in temp
      if t != nothing
          push!(tempFloat, t) ###
      end
    end

    if length(tempFloat) <= 0
      return [0.0, 0.0]
    else
      return tempFloat
    end
end

function enableACPower(su::MPSSurveillanceUnit)
  @info "Enable AC Power"
end

function disableACPower(su::MPSSurveillanceUnit)
  @info "Disable AC Power"
end
