struct FOTemp <: Device
  sd::SerialDevice
end

"""
`fotemp(portAdress::AbstractString)`

Initialize Fotemp fiber optical temperature sensor. For an overview
over the high level API call `methodswith(SerialDevice{FOTemp})`.

Low level functions such as `getModelName(ft)` will return a function hash and
a whitespace, e.g. "#40 " leading the actual answer, which would be the model
name of the device in this case.
"""
function FOTemp(portAdress::AbstractString)
	pause_ms::Int=200
	timeout_ms::Int=500
	delim_read::String="\r\n"
	delim_write::String="\r"
	baudrate::Integer = 57600
	ndatabits::Integer=8
	parity::SPParity=SP_PARITY_NONE
	nstopbits::Integer=1
	rts::SPrts=SP_RTS_OFF
	cts::SPcts=SP_CTS_IGNORE
	dtr::SPdtr=SP_DTR_OFF
	dsr::SPdsr=SP_DSR_IGNORE
	xonxoff::SPXonXoff=SP_XONXOFF_DISABLED

	sp = SerialPort(portAdress)
	open(sp)
	set_speed(sp, baudrate)
	set_frame(sp,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)

	write(sp, "?40 $delim_write")
	sleep(pause_ms/1000)
	answer = readuntil(sp, '\n', timeout_ms)
	flush(sp)
	if (answer=="#40 46 54 20 43 4F 4D 50 32\r\n")
		@info "Connection to fibre optical termometer established."
		return FoTemp( SerialDevice(sp,pause_ms,timeout_ms,delim_read,delim_write) )
	elseif (answer=="*FF\r\n")
		@warn "Failed to establish connection. Try again."
		return nothing
	else
		@warn "Connected to the wrong Device!"
		return nothing
	end
end

"""
Returns the averaged temperature of a channel.
"""
function getAveragedTemperature(ft::FOTemp,channel::Char)
	return query(ft.sd, "?01 $channel")
end

"""
Returns the averaged temperature of all channel.
"""
function getAveragedTemperature(ft::FOTemp)
	return query(ft.sd, "?02")
end

"""
Returns the current temperature of a channel.
"""
function getTemperature(ft::FOTemp,channel::Char)
	return query(ft.sd, "?03 $channel")
end

"""
Returns the current temperature of all channel.
"""
function getTemperature(ft::FOTemp)
	return query(ft.sd, "?04")
end

"""
Returns the number of channels the device has.
"""
function numChannels(ft::FOTemp)
	return query(ft.sd, "?0F")
end

"""
Returns the the active channels. The active and inactive channels are the
bits of the ASCII encoded hexadecimal bytes returned after the whitespace
following the function hash. I.e. `"#10 1E"` represents that channels 2, 3, 4,
and 5 are on and the remaining channels 1,6,7, and 8 are switched off.

"""
function getActiveChannels(ft::FOTemp)
	return query(ft.sd, "?10")
end

"""
Sets the active channels. The parameter `channel` encodes the switched on and
off channels. The bits of the ASCII encoded hexadecimal bytes are the channels,
with bit 0 representing channel 1 to bit 7 for channel 8.

For example `channel="1E"` will switch on channels 2, 3, 4, and 5 and switch
off the remaining channels 1,6,7, and 8.
"""
function setActiveChannel(ft::FOTemp, channel::String)
	send(ft.sd, ":10 $channel")
	return nothing
end

"""
Returns the index of the active channel.
"""
function getMeasuringChannels(ft::FOTemp)
	return query(ft.sd, "?12")
end

"""
Returns the model name of the device.
"""
function getModelName(ft::FOTemp)
	return query(ft.sd, "?40")
end

"""
Returns the model name of the device.
"""
function getSerialNumber(ft::FOTemp)
	return query(ft.sd, "?41")
end

"""
Returns the firmware version.
"""
function getFirmwareVersion(ft::FOTemp)
	return query(ft.sd, "?42")
end

"""
Returns the averaging count of a given `channel`.
"""
function getTemperatureAveraging(ft::FOTemp,channel::Char)
	return query(ft.sd, "?53 $channel")
end

"""
Sets the moving averaging count of a given `channel` to 0<`numAverages`<21.
"""
function setTemperatureAveraging(ft::FOTemp,channel::Char,numAverages::Integer)
	(numAverages<0 || numAverages>20) && throw(BoundsError)
	send(ft.sd, ":53 $channel $numAverages")
	return nothing
end
