import Sockets: send

export getSerialDevices, resolvedSymlink

macro add_serial_device_fields(delim)
	return esc(quote
		delim_read::Char = $delim
		delim_write::Char = $delim
  	baudrate::Integer
  	ndatabits::Integer = 8
  	parity::SPParity = SP_PARITY_NONE
  	nstopbits::Integer = 1
		timeout_ms::Int = 1000
	end)
end

function serial_device_splatting(params::DeviceParams) 
	result = Dict{Symbol,Any}()
	for field in [:delim_read, :delim_write, :baudrate, :ndatabits, :parity, :nstopbits, :timeout_ms]
		if hasfield(typeof(params), field)
			result[field] = getfield(params, field)
		else
			throw(ScannerConfigurationError("Paramter struct $(typeof(params)) is missing field $field"))
		end
	end
	return result
end

function resolvedSymlink(port::String)
  if islink(port)
    resolvedPort = joinpath("/dev", readlink(port))
  else
    resolvedPort = port
  end
  return resolvedPort
end

mutable struct SerialDevice
	sp::SerialPort
	portName::String
	timeout_ms::Int
	delim_read::Char
	delim_write::Char
end

function SerialDevice(port::SerialPort, portName::String; delim_read::Char, delim_write::Char, timeout_ms = 1000)
	return SerialDevice(port, portName, timeout_ms, delim_read, delim_write)	
end

function SerialDevice(port::String; baudrate::Integer, delim_read::Char, delim_write::Char, timeout_ms = 1000, ndatabits::Integer = 8,
	parity::SPParity = SP_PARITY_NONE, nstopbits::Integer = 1)
	sp = SerialPort(port)
	open(sp)
	set_speed(sp, baudrate)
	set_frame(sp, ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	sp_flush(sp, SP_BUF_BOTH)
	return SerialDevice(sp, port, timeout_ms, delim_read, delim_write)
end

"""
Set maximal time to wait for query answer in ms.
"""
function set_timeout_ms(sd::SerialDevice,timeout_ms::Int)
	sd.timeout_ms = timeout_ms
	return nothing
end

"""
Set character which terminates query.
"""
function set_delim_write(sd::SerialDevice,delim::String)
	sd.delim_write = delim
	return nothing
end


"""
Set character which terminates query answer.
"""
function set_delim_read(sd::SerialDevice,delim::String)
	sd.delim_read = delim
	return nothing
end

"""
Send command string to serial device.
"""
function send(sd::SerialDevice,cmd::String)
	out = string(cmd, sd.delim_write)
	@info "$(sd.portName) sent: $out"
	write(sd.sp,out)
	# Wait for all data to be transmitted
	sp_drain(sd.sp)
	return nothing
end

"""
Read out current content of the output buffer of the serial devive. Returns a String.
"""
function receive(sd::SerialDevice)
	set_read_timeout(sd.sp, sd.timeout_ms/1000)
	return read(sd.sp, String)
end

function receive(sd::SerialDevice, array::AbstractArray)
	set_read_timeout(sd.sp, sd.timeout_ms/1000)
	return read!(sd.sp, array)
end

function receiveDelimited(sd::SerialDevice, array::AbstractArray)
	set_read_timeout(sd.sp, sd.timeout_ms/1000)
	buf = IOBuffer()
	done = false
	while bytesavailable(sd.sp) > 0 || !done
		c = read(sd.sp, 1)
		if c[1] == UInt8(sd.delim_read)
			done = true
			break
		end
		write(buf, c)
	end
	seekstart(buf)
	read!(buf, array)
end

"""
Send querry to serial device and receive device answer. Returns a String
"""
function query(sd::SerialDevice,cmd::String)
	send(sd,cmd)
	out = readuntil(sd.sp, sd.delim_read)
	# Discard remaining data
	sp_flush(sd.sp, SP_BUF_INPUT)
	return out
end

function query!(sd::SerialDevice, cmd::String, data::AbstractArray; delimited::Bool=false)
	send(sd,cmd)
	if delimited
		receiveDelimited(sd, data)
	else 
		receive(sd, data)
	end
	# Discard remaining data
	sp_flush(sd.sp, SP_BUF_INPUT)
	return data
end

"""
Close the serial port of the serial device `sd`.
"""
function Base.close(sd::SerialDevice)
	close(sd.sp)
	return sd
end

"""
Read out current Serial Ports, returns `Array{String,1}`
"""
function getSerialDevices()
  return get_port_list()
end
