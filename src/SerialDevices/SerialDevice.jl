import Base: send

# abstract supertype for all possible serial devices
abstract Device

type SerialDevice{T<:Device}
	sp::SerialPort
	pause_ms::Int
	timeout_ms::Int
	delim::String
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
Set character which terminates querry answer.
"""
function set_delim(sd::SerialDevice,delim::String)
	sd.delim = delim
	return nothing
end

"""
Send command string to serial device.
"""
function send(sd::SerialDevice,cmd::String)
	write(sd.sp,cmd)
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
function querry(sd::SerialDevice,cmd::String)
	flush(sd.sp)
	send(sd,cmd)
	out = readuntil(sd.sp, sd.delim, sd.timeout_ms)
	return out
end
