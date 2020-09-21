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
    Temps = ArduinoCommand(Arduino, "GET:TEMP")
    TempDelim = "T"

    temp =  tryparse.(Float64,split(Temps,TempDelim))

    # We hardcode this to four here
    tempFloat = zeros(2)

    for i=1:min(length(tempFloat),length(temp)) 
      if temp[i] != nothing
          tempFloat[i] = temp[i]
      end
    end

    return tempFloat    
end


function enablePMPS(scanner::MPIScanner, rp::RedPitaya)
  DIO(rp,scanner.params["DAQ"]["pinRSDSM1850"],true) #activate SM18-50
  DIO(rp,scanner.params["DAQ"]["pinInterlockHubert"],true) #activate Hubert
end

function disablePMPS(scanner::MPIScanner, rp::RedPitaya)
  DIO(rp,scanner.params["DAQ"]["pinRSDSM1850"],false) #remoteshutdown SM18-50
  DIO(rp,scanner.params["DAQ"]["pinInterlockHubert"],false) #interlock Hubert
end

function enableACPower(su::MPSSurveillanceUnit, scanner::MPIScanner)
  @info "Enable AC Power"
  daq = getDAQ(scanner)
  rp = master(daq.rpc)

  temps = getTemperatures(su)
  tempMax = scanner.params["SurveillanceUnit"]["maxTemperatures"]
  
  #code for pMPS
  if scanner.params["General"]["scannerName"] == "pMPS"
    if iszero(temps .> tempMax) != false
      @info "pMPS: Hubert interlock and RSD off. Ready to measure."
      enablePMPS(scanner, rp)
    else
      @warn "pMPS: maxTemp exceeded. Hubert interlock and RSD stay on." temps tempMax
      disablePMPS(scanner, rp)
    end  
  end
end

function disableACPower(su::MPSSurveillanceUnit, scanner::MPIScanner)
  @info "Disable AC Power"
  daq = getDAQ(scanner)
  rp = master(daq.rpc)

  #code for pMPS
  if scanner.params["General"]["scannerName"] == "pMPS"
      @info "pMPS: Hubert interlock and RSD on."
      disablePMPS(scanner, rp)
  end 
end
