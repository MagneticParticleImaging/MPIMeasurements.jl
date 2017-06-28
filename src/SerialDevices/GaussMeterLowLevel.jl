export gaussMeter

abstract GaussMeter <: Device

"""
`gaussMeter(portAdress::AbstractString)`

Initialize Model 460 3 Channel Gaußmeter on port `portAdress`. For an overview
over the high level API call `methodswith(SerialDevice{GaussMeter})`.
"""
function gaussMeter(portAdress::AbstractString)
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
			return SerialDevice{GaussMeter}(sp,pause_ms,timeout_ms,delim_read,delim_write)
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
function identification(sd::SerialDevice{GaussMeter})
	return querry(sd, "*IDN?")
end

"""
The gaussmeter reports status based on test done at power up. 0 = no erors found, 1= erros found
"""
function selfTest(sd::SerialDevice{GaussMeter})
	out = querry(sd, "*TST?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Returns the mode of the active channel DC = 0 AC = 1
"""
function getMode(sd::SerialDevice{GaussMeter})
	return querry(sd, "ACDC?")
end

"""
Set the mode for the channel DC = 0 AC = 1
"""
function setMode(sd::SerialDevice{GaussMeter}, channel::Char, mode::Char)
	setActiveChannel(sd, channel)
	send(sd, "ACDC $mode")
end

"""
Set the mode of all channels DC = 0, AC = 1
"""
function setAllMode(sd::SerialDevice{GaussMeter}, mode::Char)
	setMode(sd, 'x', mode)
	setMode(sd, 'Y', mode)
	setMode(sd, 'Z', mode)
end

"""
Returns the AC Mode RMS = 0, Peak = 1
"""
function getPeakRMS(sd::SerialDevice{GaussMeter})
	return querry(sd, "PRMS?")
end

"""
Set the AC mode for the channel RMS = 0, Peak = 1
"""
function setPeakRMS(sd::SerialDevice{GaussMeter}, channel::Char, mode::Char)
	setActiveChannel(sd, channel)
	send(sd, "PRMS $mode")
end

"""
Returns the sleep mode status of the gaussmeter
"""
function isInSleepMode(sd::SerialDevice{GaussMeter})
	out = querry(sd, "SLEEP?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Sets the sleep mode state of the gaussmeter.  0 = on, 1 = off
"""
function setSleepMode(sd::SerialDevice{GaussMeter}, state::Char)
	send(sd, "SLEEP $state")
end

"""
Returns the state of the frontpanel lock
"""
function isLocked(sd::SerialDevice{GaussMeter})
	out = querry(sd, "LOCK?")
	if out == "1"
		return true
	elseif out == "0"
		return false
	end
end

"""
sets the state of the front panel lock. Locks all entries except the alarm keys. 1 = on, 0 = off
"""
function setFrontPanelLock(sd::SerialDevice{GaussMeter}, state::Char)
	send(sd, "LOCK $state")
end

"""
Returns the active channel X, Y, Z, V = Vector Magnitude Channel
"""
function getActiveChannel(sd::SerialDevice{GaussMeter})
	return querry(sd, "CHNL?")
end

"""
Sets the active channel to X, Y, Z, V = Vector Magnitude Channel
"""
function setActiveChannel(sd::SerialDevice{GaussMeter}, channel::Char)
	send(sd, "CHNL $channel")
end

"""
Returns the active used unit G = gauss, T = tesla
"""
function getUnit(sd::SerialDevice{GaussMeter})
	return querry(sd, "UNIT?")
end

"""
Sets the active unit to `'G'` = gauss, `'T'` = tesla
"""
function setUnit(sd::SerialDevice{GaussMeter}, unit::Char)
	send(sd, "UNIT $unit")
end

"""
Returns the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = +-3T
	1						= +-300mT
	2						= +-30mT
	3 = lowest	= +-3mT
"""
function getRange(sd::SerialDevice{GaussMeter})
	return querry(sd, "RANGE?")
end

"""
Sets the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = +-3T
	1						= +-300mT
	2						= +-30mT
	3 = lowest	= +-3mT
"""
function setRange(sd::SerialDevice{GaussMeter}, range::Char)
	send(sd, "RANGE $range")
end

"""
Returns the state of auto ranging for the active channel
"""
function isAutoRanging(sd::SerialDevice{GaussMeter})
	out = querry(sd, "AUTO?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set state of auto ranging for the active channel
"""
function setAutoRanging(sd::SerialDevice{GaussMeter}, state::Char)
	send(sd, "AUTO $range")
end


"""
Returns the state of the probe of the active channel
"""
function isProbeOn(sd::SerialDevice{GaussMeter})
	out = querry(sd, "ONOFF?")
	if out == "1"
		return false
	elseif out == "0"
		return true
	end
end

"""
Sets probe on = 0 or off = 1 on specific channel
"""
function setProbe(sd::SerialDevice{GaussMeter}, channel::Char, state::Char)
	setActiveChannel(sd, channel)
	send(sd, "ONOFF $state")
end

"""
Sets complete probe on = 0 or off = 1
"""
function setCompleteProbe(sd::SerialDevice{GaussMeter}, state::Char)
	setProbe(sd, 'X', state)
	setProbe(sd, 'Y', state)
	setProbe(sd, 'Z', state)
end

"""
Returns the type of the probe
	0 = High Sensitivity (HSE)
	1 = High Stability (HST)
	2 = Ultra-High Sensitivity (UHS)
"""
function getProbeType(sd::SerialDevice{GaussMeter})
	return querry(sd, "TYPE?")
end

"""
Returns the field value of the active channel
"""
function getField(sd::SerialDevice{GaussMeter})
	return querry(sd, "FIELD?")
end

"""
Returns the field values of X, Y, Z , V = Vector Magnitude
"""
function getAllFields(sd::SerialDevice{GaussMeter})
	return querry(sd, "ALLF?")
end

"""
Returns the state of the field compensation
"""
function isFieldComp(sd::SerialDevice{GaussMeter})
	out = querry(sd, "FCOMP?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set the state of the field compensation. 1 = on, 0 = off
"""
function setFieldComp(sd::SerialDevice{GaussMeter}, state::Char)
	send(sd, "FCOMP $state")
end

"""
Returns the state of the temperatur compensation
"""
function isTempComp(sd::SerialDevice{GaussMeter})
	out = querry(sd, "TCOMP?")
	if out == "0"
		return false
	elseif out == "1"
		return true
	end
end

"""
Set the state of the temperatur compensation. 1 = on, 0 = off
"""
function setTempComp(sd::SerialDevice{GaussMeter}, state::Char)
	send(sd, "TCOMP $state")
end
