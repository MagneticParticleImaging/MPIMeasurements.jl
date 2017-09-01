export getXValue,getYValue,getZValue,getVectorMagnitude
export setXRange,setYRange,setZRange,setAllRange
export sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToGauss,setUnitToTesla,setStandardSettings
export getRange

include("GaussMeterLowLevel.jl")

"""
Returns the value of the X channel
"""
function getXValue(gauss::GaussMeter)
	setActiveChannel(gauss, 'X')
	return parse(Float32,getField(sd))
end

"""
Returns the value of the Y channel
"""
function getYValue(gauss::GaussMeter)
	setActiveChannel(gauss, 'Y')
	return parse(Float32,getField(sd))
end

"""
Returns the value of the Z channel
"""
function getZValue(gauss::GaussMeter)
	setActiveChannel(gauss, 'Z')
	return parse(Float32,getField(sd))
end

"""
Returns the value of the vector magnitude sqrt(X² + Y² +Z²)
"""
function getVectorMagnitude(gauss::GaussMeter)
	setActiveChannel(gauss, 'V')
	return parse(Float32,getField(sd))
end

"""
Sets the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = +-3T
	1						= +-300mT
	2						= +-30mT
	3 = lowest	= +-3mT


Sets the range of the X channel
"""
function setXRange(gauss::GaussMeter, range::Char)
	setActiveChannel(gauss, 'X')
	setRange(gauss, range)
	return nothing
end

"""
Sets the range of the Y channel
"""
function setYRange(gauss::GaussMeter, range::Char)
	setActiveChannel(gauss, 'Y')
	setRange(gauss, range)
	return nothing
end

"""
Sets the range of the Z channel
"""
function setZRange(gauss::GaussMeter, range::Char)
	setActiveChannel(gauss, 'Z')
	setRange(gauss, range)
	return nothing
end

"""
Stes the range of all channels
"""
function setAllRange(gauss::GaussMeter, range::Char)
	setXRange(gauss, range)
	setYRange(gauss, range)
	setZRange(gauss, range)
	return nothing
end

"""
Sets the sleep mode on
"""
function sleepModeOn(gauss::GaussMeter)
	setSleepMode(sd, '0')
	return nothing
end

"""
Sets the sleep mode off
"""
function sleepModeOff(gauss::GaussMeter)
	setSleepMode(sd, '1')
	return nothing
end

"""
Locks the frontpanel
"""
function lockOn(gauss::GaussMeter)
	setFrontPanelLock(sd, '1')
	return nothing
end

"""
Unlocks the frontpanel
"""
function lockOff(gauss::GaussMeter)
	setFrontPanelLock(sd, '0')
	return nothing
end

"""
Sets the unit of the values to gauss
"""
function setUnitToGauss(gauss::GaussMeter)
	setUnit(gauss, 'G')
	return nothing
end

"""
Sets the unit of the values to tesla
"""
function setUnitToTesla(gauss::GaussMeter)
	setUnit(gauss, 'T')
	return nothing
end

"""
Sets the standard settings
	-highest range
	-unit to tesla
	-auto ranging off
	-complete probe on
"""
function setStandardSettings(gauss::GaussMeter)
	setAllRange(gauss, '0')
	setAllMode(gauss, '0')
	setUnitToTesla(gauss)
	setAutoRanging(gauss, '0')
	setCompleteProbe(gauss, '0')
	println("Standard Settings set.")
	println("Unit = Tesla, Range = lowest, Mode = DC, AutoRanging = off, Probe = on")
	return nothing
end
