export getXYZValues
export setAllRange
export sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToTesla,setStandardSettings, getFieldError

include("LakeShoreLowLevel.jl")

function LakeShoreGaussMeter(params::Dict)
  gauss = LakeShoreGaussMeter(params["connection"], params["coordinateTransformation"])

  setStandardSettings(gauss)

  setAllAutoRanging(gauss, params["autoRanging"] ? '1' : '0')
  if !params["autoRanging"]
    setAllRange(gauss, string(params["range"])[1])
  end

  setFast(gauss, params["fast"] ? '1' : '0')
  return gauss
end

"""
Returns x,y, and z values and apply a coordinate transformation
"""
function getXYZValues(gauss::LakeShoreGaussMeter)
	field = parse.(Float32,split(getAllFields(gauss),","))[1:3]
	multipliers = getAllMultipliers(gauss)
    gauss.coordinateTransformation*(field.*multipliers)*Unitful.T
end

"""
Sets the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = ±3T
	1           = ±300mT
	2           = ±30mT
	3 = lowest  = ±3mT

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

function getFieldError(range::Int)
    if range == 0
        return 150Unitful.μT
    elseif range == 1
        return 15Unitful.μT
    elseif range == 2
        return 1.5Unitful.μT
    elseif range == 3
        return 0.15Unitful.μT
    end
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
	#setAllRange(gauss, '0')
	#setAllMode(gauss, '0')
	setAllAutoRanging(gauss, '1')
	setUnitToTesla(gauss)
	setCompleteProbe(gauss, '0')
	@info "Standard Settings: Unit = Tesla, Range = lowest, Mode = DC, AutoRanging = off, Probe = on"
	return nothing
end
