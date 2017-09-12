export GaussMeter

struct GaussMeter <: AbstractGaussMeter
  sd::SerialDevice
end

"""
`GaussMeter(portAdress::AbstractString)`

Initialize Model 460 3 Channel Gaußmeter on port `portAdress`. For an overview
over the high level API call `methodswith(SerialDevice{GaussMeter})`.
"""
function GaussMeter(portAdress::AbstractString)
	pause_ms::Int=400
	timeout_ms::Int=500
	delim_read::String="\r\n"
	delim_write::String="\r\n"
	baudrate::Integer = 9600
	ndatabits::Integer=7
	parity::SPParity=SP_PARITY_ODD
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

	flush(sp)
	write(sp, "*IDN?$delim_write")
	sleep(pause_ms/1000)
	if(readuntil(sp, delim_read, timeout_ms) == "LSCI,MODEL460,0,032406$delim_read")

		println("Connected to LSCI,MODEL460,0,032406.")
		flush(sp)
		write(sp, "*TST?$delim_write")
		sleep(pause_ms/1000)
		if(readuntil(sp, delim_read, timeout_ms) == "0$delim_read")

			println("No Errors found.")
			return GaussMeter( SerialDevice(sp,pause_ms, timeout_ms, delim_read, delim_write) )
		else
			println("Errors found in the Device!")
		end
	else
		println("Connected to the wrong Device!")
	end
end

"""
Returns the manufacturerID, model number, derial number and firmware revision date
"""
function identification(gauss::GaussMeter)
	return query(gauss.sd, "*IDN?")
end

"""
The gaussmeter reports status based on test done at power up. 0 = no erors found, 1= erros found
"""
function selfTest(gauss::GaussMeter)
	out = query(gauss.sd, "*TST?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Returns the mode of the active channel DC = 0 AC = 1
"""
function getMode(gauss::GaussMeter)
	return query(gauss.sd, "ACDC?")
end

"""
Set the mode for the channel DC = 0 AC = 1
"""
function setMode(gauss::GaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ACDC $mode")
end

"""
Set the mode of all channels DC = 0, AC = 1
"""
function setAllMode(gauss::GaussMeter, mode::Char)
	setMode(gauss, 'x', mode)
	setMode(gauss, 'Y', mode)
	setMode(gauss, 'Z', mode)
end

"""
Returns the AC Mode RMS = 0, Peak = 1
"""
function getPeakRMS(gauss::GaussMeter)
	return query(gauss.sd, "PRMS?")
end

"""
Set the AC mode for the channel RMS = 0, Peak = 1
"""
function setPeakRMS(gauss::GaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "PRMS $mode")
end

"""
Returns the sleep mode status of the gaussmeter
"""
function isInSleepMode(gauss::GaussMeter)
	out = query(gauss.sd, "SLEEP?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Sets the sleep mode state of the gaussmeter.  0 = on, 1 = off
"""
function setSleepMode(gauss::GaussMeter, state::Char)
	send(gauss.sd, "SLEEP $state")
end

"""
Returns the state of the frontpanel lock
"""
function isLocked(gauss::GaussMeter)
	out = query(gauss.sd, "LOCK?")
	if out == "1"
		return true
	elseif out == "0"
		return false
	end
end

"""
Fast data command mode query.  0 = on, 1 = off
"""
function getFast(gauss::GaussMeter)
	return query(gauss.sd, "FAST?")
end

"""
Set fast data command mode.  0 = on, 1 = off
"""
function setFast(gauss::GaussMeter, state::Char)
	send(gauss.sd, "FAST $state")
end

"""
sets the state of the front panel lock. Locks all entries except the alarm keys. 1 = on, 0 = off
"""
function setFrontPanelLock(gauss::GaussMeter, state::Char)
	send(gauss.sd, "LOCK $state")
end

"""
Returns the active channel X, Y, Z, V = Vector Magnitude Channel
"""
function getActiveChannel(gauss::GaussMeter)
	return query(gauss.sd, "CHNL?")
end

"""
Sets the active channel to X, Y, Z, V = Vector Magnitude Channel
"""
function setActiveChannel(gauss::GaussMeter, channel::Char)
	send(gauss.sd, "CHNL $channel")
end

"""
Returns the active used unit G = gauss, T = tesla
"""
function getUnit(gauss::GaussMeter)
	return query(gauss.sd, "UNIT?")
end

"""
Sets the active unit to `'G'` = gauss, `'T'` = tesla
"""
function setUnit(gauss::GaussMeter, unit::Char)
	send(gauss.sd, "UNIT $unit")
end

"""
Returns the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = +-3T
	1						= +-300mT
	2						= +-30mT
	3 = lowest	= +-3mT
"""
function getRange(gauss::GaussMeter)
	return query(gauss.sd, "RANGE?")
end

"""
Sets the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = +-3T
	1						= +-300mT
	2						= +-30mT
	3 = lowest	= +-3mT
"""
function setRange(gauss::GaussMeter, range::Char)
	send(gauss.sd, "RANGE $range")
end

"""
Returns the state of auto ranging for the active channel
"""
function isAutoRanging(gauss::GaussMeter)
	out = query(gauss.sd, "AUTO?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set state of auto ranging for the active channel
"""
function setAutoRanging(gauss::GaussMeter, state::Char)
	send(gauss.sd, "AUTO $range")
end


"""
Returns the state of the probe of the active channel
"""
function isProbeOn(gauss::GaussMeter)
	out = query(gauss.sd, "ONOFF?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Sets probe on = 0 or off = 1 on specific channel
"""
function setProbe(gauss::GaussMeter, channel::Char, state::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ONOFF $state")
end

"""
Sets complete probe on = 0 or off = 1
"""
function setCompleteProbe(gauss::GaussMeter, state::Char)
	setProbe(gauss, 'X', state)
	setProbe(gauss, 'Y', state)
	setProbe(gauss, 'Z', state)
end

"""
Returns the type of the probe
	0 = High Sensitivity (HSE)
	1 = High Stability (HST)
	2 = Ultra-High Sensitivity (UHS)
"""
function getProbeType(gauss::GaussMeter)
	return query(gauss.sd, "TYPE?")
end

"""
Returns the field value of the active channel
"""
function getField(gauss::GaussMeter)
	return query(gauss.sd, "FIELD?")
end

"""
Returns the field values of X, Y, Z , V = Vector Magnitude
"""
function getAllFields(gauss::GaussMeter)
	return query(gauss.sd, "ALLF?")
end

"""
Returns the state of the field compensation
"""
function isFieldComp(gauss::GaussMeter)
	out = query(gauss.sd, "FCOMP?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set the state of the field compensation. 1 = on, 0 = off
"""
function setFieldComp(gauss::GaussMeter, state::Char)
	send(gauss.sd, "FCOMP $state")
end

"""
Returns the state of the temperatur compensation
"""
function isTempComp(gauss::GaussMeter)
	out = query(gauss.sd, "TCOMP?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set the state of the temperatur compensation. 1 = on, 0 = off
"""
function setTempComp(gauss::GaussMeter, state::Char)
	send(gauss.sd, "TCOMP $state")
end
