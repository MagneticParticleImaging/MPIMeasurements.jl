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
	delim::String="/r/n"
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
	write(sp, string("*IDN?", delim))
	sleep(pause_ms/1000)
	if(readuntil(sp, delim, timeout_ms)[1:end-2] == "LSCI,MODEL460,0,032406")

		println("Connected to LSCI,MODEL460,0,032406.")
		flush(sp)
		write(sp, string("*TST?", delim))
		sleep(pause_ms/1000)
		if(readuntil(sp, delim, timeout_ms)[1:end-2] == "0")

			println("No Errors found.")
			return SerialDevice{GaussMeter}(sp,pause_ms,timeout_ms,delim)
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
	return querry(sd, string("*IDN?", sd.delim))[1:end-2]
end

"""
The gaussmeter reports status based on test done at power up. 0 = no erors found, 1= erros found
"""
function selfTest(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("*TST?", sd.delim))[1:end-2]
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
	return querry(sd, string("ACDC?", sd.delim))[1:end-2]
end

"""
Set the mode for the channel DC = 0 AC = 1
"""
function setMode(sd::SerialDevice{GaussMeter}, channel::Char, mode::Char)
	setActiveChannel(sd, channel)
	send(sd, string("ACDC ", mode, sd.delim))
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
	return querry(sd, string("PRMS?", sd.delim))[1:end-2]
end

"""
Set the AC mode for the channel RMS = 0, Peak = 1
"""
function setPeakRMS(sd::SerialDevice{GaussMeter}, channel::Char, mode::Char)
	setActiveChannel(sd, channel)
	send(sd, string("PRMS ", mode, sd.delim))
end

"""
Returns the sleep mode status of the gaussmeter
"""
function isInSleepMode(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("SLEEP?", sd.delim))[1:end-2]
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
	send(sd, string("SLEEP ", state, sd.delim))
end

"""
Returns the state of the frontpanel lock
"""
function isLocked(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("LOCK?", sd.delim))[1:end-2]
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
	send(sd, string("LOCK ", state, sd.delim))
end

"""
Returns the active channel X, Y, Z, V = Vector Magnitude Channel
"""
function getActiveChannel(sd::SerialDevice{GaussMeter})
	return querry(sd, string("CHNL?", sd.delim))[1:end-2]
end

"""
Sets the active channel to X, Y, Z, V = Vector Magnitude Channel
"""
function setActiveChannel(sd::SerialDevice{GaussMeter}, channel::Char)
	send(sd, string("CHNL ", channel, sd.delim))
end

"""
Returns the active used unit G = gauss, T = tesla
"""
function getUnit(sd::SerialDevice{GaussMeter})
	return querry(sd, string("UNIT?", sd.delim))[1:end-2]
end

"""
Sets the active unit to `'G'` = gauss, `'T'` = tesla
"""
function setUnit(sd::SerialDevice{GaussMeter}, unit::Char)
	send(sd, string("UNIT ", unit, sd.delim))
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
	return querry(sd, string("RANGE?", sd.delim))[1:end-2]
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
	send(sd, string("RANGE ", range, sd.delim))
end

"""
Returns the state of auto ranging for the active channel
"""
function isAutoRanging(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("AUTO?", sd.delim))[1:end-2]
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
	send(sd, string("AUTO ", range, sd.delim))
end


"""
Returns the state of the probe of the active channel
"""
function isProbeOn(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("ONOFF?", sd.delim))[1:end-2]
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
	send(sd, string("ONOFF", state, sd.delim))
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
	return querry(sd, string("TYPE?", sd.delim))[1:end-2]
end

"""
Returns the field value of the active channel
"""
function getField(sd::SerialDevice{GaussMeter})
	return querry(sd, string("FIELD?", sd.delim))[1:end-2]
end

"""
Returns the field values of X, Y, Z , V = Vector Magnitude
"""
function getAllFields(sd::SerialDevice{GaussMeter})
	return querry(sd, string("ALLF?", sd.delim))[1:end-2]
end

"""
Returns the state of the field compensation
"""
function isFieldComp(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("FCOMP?", sd.delim))[1:end-2]
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
	send(sd, string("FCOMP ", state, sd.delim))
end

"""
Returns the state of the temperatur compensation
"""
function isTempComp(sd::SerialDevice{GaussMeter})
	out = querry(sd, string("TCOMP?", sd.delim))[1:end-2]
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
	send(sd, string("TCOMP ", state, sd.delim))
end
