import Sockets: send

export getSerialDevices, resolvedSymlink

macro add_serial_device_fields(delim)
	return esc(quote
		delim_read::Union{Char, Nothing} = $delim
		delim_write::Union{Char, Nothing} = $delim
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
	delim_read::Union{Char, Nothing}
	delim_write::Union{Char, Nothing}
	sdLock::ReentrantLock
	SerialDevice(sp, portName, timeout_ms, delim_read, delim_write) = new(sp, portName, timeout_ms, delim_read, delim_write, ReentrantLock())
end

function SerialDevice(port::SerialPort, portName::String; delim_read::Union{Char, Nothing} = nothing, delim_write::Union{Char, Nothing} = nothing, timeout_ms = 1000)
	return SerialDevice(port, portName, timeout_ms, delim_read, delim_write)	
end

function SerialDevice(port::String; baudrate::Integer, delim_read::Union{Char, Nothing} = nothing, delim_write::Union{Char, Nothing} = nothing, timeout_ms = 1000, ndatabits::Integer = 8,
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
	lock(sd.sdLock)
	try
		out = cmd
		if !isnothing(sd.delim_write)
			out = string(cmd, sd.delim_write)
		end
		@debug "$(sd.portName) sent: $out"
		write(sd.sp,out)
		# Wait for all data to be transmitted
		sp_drain(sd.sp)
		return nothing
	finally
		unlock(sd.sdLock)
	end
end

function send(sd::SerialDevice, cmd::Vector{UInt8})
	lock(sd.sdLock)
	try
		write(sd.sp, cmd)
		@debug "$(sd.portName) sent: $cmd"
		sp_drain(sd.sp)
		return nothing
	finally
		unlock(sd.sdLock)
	end
end

"""
Read out current content of the output buffer of the serial devive. Returns a String.
"""
function receive(sd::SerialDevice)
	lock(sd.sdLock)
	try
		#set_read_timeout(sd.sp, sd.timeout_ms/1000)
		reply = readuntil(sd.sp, sd.delim_read)
		@debug "$(sd.portName) received: $reply"
		return reply
	finally
		unlock(sd.sdLock)
	end
end

function receive(sd::SerialDevice, array::AbstractArray)
	lock(sd.sdLock)
	try
		set_read_timeout(sd.sp, sd.timeout_ms/1000)
		return read!(sd.sp, array)
	finally
		unlock(sd.sdLock)
	end
end

function receiveDelimited(sd::SerialDevice, array::AbstractArray)
	lock(sd.sdLock)
	try
		println("----------------------------")
		set_read_timeout(sd.sp, sd.timeout_ms/1000)
		buf = IOBuffer()
		done = false
		while bytesavailable(sd.sp) > 0 || !done
			c = read(sd.sp, 1)
			println(c[1])
			if c[1] == UInt8(sd.delim_read) && buf.size == sizeof(array)
				println("we did it")
				done = true
				break
			end
			write(buf, c)
		end
		seekstart(buf)
		read!(buf, array)
	finally
		unlock(sd.sdLock)
	end
end

"""
Send querry to serial device and receive device answer. Returns a String
"""
function query(sd::SerialDevice,cmd)
	lock(sd.sdLock)
	try
		sp_flush(sd.sp, SP_BUF_INPUT)
		send(sd,cmd)
		out = receive(sd)
		# Discard remaining data
		sp_flush(sd.sp, SP_BUF_INPUT)
		return out
	finally
		sp_flush(sd.sp, SP_BUF_INPUT)
		unlock(sd.sdLock)
	end
end

function query!(sd::SerialDevice, cmd, data::AbstractArray; delimited::Bool=false)
	lock(sd.sdLock)
	try
		sp_flush(sd.sp, SP_BUF_INPUT)
		send(sd,cmd)
		if delimited
			receiveDelimited(sd, data)
		else 
			receive(sd, data)
		end
		# Discard remaining data
		sp_flush(sd.sp, SP_BUF_INPUT)
		return data
	finally
		unlock(sd.sdLock)
	end
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
