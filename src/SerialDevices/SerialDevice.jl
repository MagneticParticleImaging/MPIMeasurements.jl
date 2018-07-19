import Base: send

export getSerialDevices

type SerialDevice
	sp::SerialPort
	pause_ms::Int
	timeout_ms::Int
	delim_read::String
	delim_write::String
end

"""
Set time to wait in ms for command to be send to serial device.
"""
function set_pause_ms(sd::SerialDevice,pause_ms::Int)
	sd.pause_ms = pause_ms
	return nothing
end

"""
Set maximal time to wait for querry answer in ms.
"""
function set_timeout_ms(sd::SerialDevice,timeout_ms::Int)
	sd.timeout_ms = timeout_ms
	return nothing
end

"""
Set character which terminates querry.
"""
function set_delim_write(sd::SerialDevice,delim::String)
	sd.delim_write = delim
	return nothing
end


"""
Set character which terminates querry answer.
"""
function set_delim_read(sd::SerialDevice,delim::String)
	sd.delim_read = delim
	return nothing
end

"""
Send command string to serial device.
"""
function send(sd::SerialDevice,cmd::String)
	write(sd.sp,string(cmd,sd.delim_write))
	sleep(sd.pause_ms/1000)
	return nothing
end

"""
Read out current content of the output buffer of the serial devive. Returns a String.
"""
function receive(sd::SerialDevice)
	return readstring(sd.sp)
end

"""
Send querry to serial device and receive device answer. Returns a String
"""
function query(sd::SerialDevice,cmd::String)
	flush(sd.sp)
	send(sd,string(cmd,sd.delim_write))
	out = readuntil(sd.sp, sd.delim_read, sd.timeout_ms)
	flush(sd.sp)
	return rstrip(out,Vector{Char}(sd.delim_read))
end

"""
Close the serial port of the serial device `sd`. The optional `delete` keyword
argument triggers a call to `sp_free_port` in the C library if set to `true`.
"""
function Base.close(sd::SerialDevice; delete::Bool=false)
	sd.sp = close(sd.sp,delete=delete)
	return sd
end

"""
Read out current Serial Ports, returns `Array{String,1}`
"""
function getSerialDevices()
    nports_guess=64
    ports = sp_list_ports()
    devices=Array{String,1}()
    portArray=unsafe_wrap(Array, ports, nports_guess, false)
    for k=1:length(portArray)
      #println(portArray[k])
        if portArray[k] == C_NULL
          return devices
        else
          try
            device=sp_get_port_name(portArray[k])
            push!(devices,device)
            #println(device)
          catch e
            println(e)
          end
        end
    end
    return devices
end
