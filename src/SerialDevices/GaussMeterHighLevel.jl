export getXValue,getYValue,getZValue,getVectorMagnitude,setXRange,setYRange
export setZRange,setAllRange,sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToGauss,setUnitToTesla,setStandardSettings

"""
Returns the value of the X channel
"""
function getXValue(sd::SerialDevice{GaussMeter})
  setActiveChannel(sd, 'X')
  return getField(sd)
end

"""
Returns the value of the Y channel
"""
function getYValue(sd::SerialDevice{GaussMeter})
  setActiveChannel(sd, 'Y')
  return getField(sd)
end

"""
Returns the value of the Z channel
"""
function getZValue(sd::SerialDevice{GaussMeter})
  setActiveChannel(sd, 'Z')
  return getField(sd)
end

"""
Returns the value of the vector magnitude sqrt(X² + Y² +Z²)
"""
function getVectorMagnitude(sd::SerialDevice{GaussMeter})
  setActiveChannel(sd, 'V')
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
function setXRange(sd::SerialDevice{GaussMeter}, range::Char)
  setActiveChannel(sd, 'X')
  setRange(sd, range)
end

"""
Sets the range of the Y channel
"""
function setYRange(sd::SerialDevice{GaussMeter}, range::Char)
  setActiveChannel(sd, 'Y')
  setRange(sd, range)
end

"""
Sets the range of the Z channel
"""
function setZRange(sd::SerialDevice{GaussMeter}, range::Char)
  setActiveChannel(sd, 'Z')
  setRange(sd, range)
end

"""
Stes the range of all channels
"""
function setAllRange(sd::SerialDevice{GaussMeter}, range::Char)
	setXRange(sd, range)
	setYRange(sd, range)
	setZRange(sd, range)
end

"""
Sets the sleep mode on
"""
function sleepModeOn(sd::SerialDevice{GaussMeter})
  setSleepMode(sd, '0')
end

"""
Sets the sleep mode off
"""
function sleepModeOff(sd::SerialDevice{GaussMeter})
  setSleepMode(sd, '1')
end

"""
Locks the frontpanel
"""
function lockOn(sd::SerialDevice{GaussMeter})
  setFrontPanelLock(sd, '1')
end

"""
Unlocks the frontpanel
"""
function lockOff(sd::SerialDevice{GaussMeter})
  setFrontPanelLock(sd, '0')
end

"""
Sets the unit of the values to gauss
"""
function setUnitToGauss(sd::SerialDevice{GaussMeter})
  setUnit(sd, 'G')
end

"""
Sets the unit of the values to tesla
"""
function setUnitToTesla(sd::SerialDevice{GaussMeter})
  setUnit(sd, 'T')
end

"""
Sets the standard settings
	-highest range
	-unit to tesla
	-auto ranging off
	-complete probe on
"""
function setStandardSettings(sd::SerialDevice{GaussMeter})
	setAllRange(sd, '0')
	setAllMode(sd, '0')
	setUnitToTesla(sd)
	setAutoRanging(sd, '0')
	setCompleteProbe(sd, '0')
	println("Standard Settings set.")
	println("Unit = Tesla, Range = lowest, Mode = DC, AutoRanging = off, Probe = on")
end