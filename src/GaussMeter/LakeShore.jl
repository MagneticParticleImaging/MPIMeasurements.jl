export getXValue,getYValue,getZValue,getVectorMagnitude
export setXRange,setYRange,setZRange,setAllRange
export sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToGauss,setUnitToTesla,setStandardSettings
export getRange

include("LakeShoreLowLevel.jl")

function LakeShoreGaussMeter(params::Dict)
  gauss = LakeShoreGaussMeter(params["connection"], params["coordinateTransformation"])

  setStandardSettings(gauss)
  setAllRange(gauss, string(params["range"])[1])
  setFast(gauss, params["fast"] ? '1' : '0')
  return gauss
end

"""
Returns the value of the X channel
"""
function getXValue(gauss::LakeShoreGaussMeter)
	setActiveChannel(gauss, 'X')
	return parse(Float32,getField(gauss))
end

"""
Returns the value of the Y channel
"""
function getYValue(gauss::LakeShoreGaussMeter)
	setActiveChannel(gauss, 'Y')
	return parse(Float32,getField(gauss))
end

"""
Returns the value of the Z channel
"""
function getZValue(gauss::LakeShoreGaussMeter)
	setActiveChannel(gauss, 'Z')
	return parse(Float32,getField(gauss))
end

"""
Returns x,y, and z values and apply a coordinate transformation
"""
function getXYZValues(gauss::LakeShoreGaussMeter)
    gauss.coordinateTransformation*[getXValue(gauss),
		 getYValue(gauss),
		 getZValue(gauss)]
end

"""
Returns the value of the vector magnitude sqrt(X² + Y² +Z²)
"""
function getVectorMagnitude(gauss::LakeShoreGaussMeter)
	setActiveChannel(gauss, 'V')
	return parse(Float32,getField(gauss))
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
function setXRange(gauss::LakeShoreGaussMeter, range::Char)
	setActiveChannel(gauss, 'X')
	setRange(gauss, range)
	return nothing
end

"""
Sets the range of the Y channel
"""
function setYRange(gauss::LakeShoreGaussMeter, range::Char)
	setActiveChannel(gauss, 'Y')
	setRange(gauss, range)
	return nothing
end

"""
Sets the range of the Z channel
"""
function setZRange(gauss::LakeShoreGaussMeter, range::Char)
	setActiveChannel(gauss, 'Z')
	setRange(gauss, range)
	return nothing
end

"""
Sets the range of all channels
"""
function setAllRange(gauss::LakeShoreGaussMeter, range::Char)
	setXRange(gauss, range)
	setYRange(gauss, range)
	setZRange(gauss, range)
	return nothing
end

"""
Sets the sleep mode on
"""
function sleepModeOn(gauss::LakeShoreGaussMeter)
	setSleepMode(gauss, '0')
	return nothing
end

"""
Sets the sleep mode off
"""
function sleepModeOff(gauss::LakeShoreGaussMeter)
	setSleepMode(gauss, '1')
	return nothing
end

"""
Locks the frontpanel
"""
function lockOn(gauss::LakeShoreGaussMeter)
	setFrontPanelLock(gauss, '1')
	return nothing
end

"""
Unlocks the frontpanel
"""
function lockOff(gauss::LakeShoreGaussMeter)
	setFrontPanelLock(gauss, '0')
	return nothing
end

"""
Sets the unit of the values to gauss
"""
function setUnitToGauss(gauss::LakeShoreGaussMeter)
	setUnit(gauss, 'G')
	return nothing
end

"""
Sets the unit of the values to tesla
"""
function setUnitToTesla(gauss::LakeShoreGaussMeter)
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
function setStandardSettings(gauss::LakeShoreGaussMeter)
	setAllRange(gauss, '0')
	setAllMode(gauss, '0')
	setUnitToTesla(gauss)
	setAutoRanging(gauss, '0')
	setCompleteProbe(gauss, '0')
	println("Standard Settings set.")
	println("Unit = Tesla, Range = lowest, Mode = DC, AutoRanging = off, Probe = on")
	return nothing
end
