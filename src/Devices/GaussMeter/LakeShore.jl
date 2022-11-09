export setAllRange
export sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToTesla,setStandardSettings, getFieldError, calculateFieldError

abstract type LakeShoreGaussMeterParams <: DeviceParams end

Base.@kwdef struct LakeShoreGaussMeterDirectParams <: LakeShoreGaussMeterParams
	portAddress::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
	autoRange::Bool = true
	range::Char = "3"
	completeProbe::Char = '1'
	fast::Bool = true
	@add_serial_device_fields "\r\n"
end
LakeShoreGaussMeterDirectParams(dict::Dict) = params_from_dict(LakeShoreGaussMeterDirectParams, dict)

Base.@kwdef struct LakeShoreGaussMeterPoolParams <: LakeShoreGaussMeterParams
	description::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
	autoRange::Bool = true
	range::Char = "3"
	completeProbe::Char = '1'
	fast::Bool = true
	@add_serial_device_fields "\r\n"
end
LakeShoreGaussMeterPoolParams(dict::Dict) = params_from_dict(LakeShoreGaussMeterPoolParams, dict)

Base.@kwdef mutable struct LakeShoreGaussMeter <: GaussMeter
	@add_device_fields LakeShoreF71GaussMeterParams
	sd::Union{SerialDevice, Nothing}
end 

neededDependencies(::LakeShoreGaussMeter) = []
optionalDependencies(::LakeShoreGaussMeter) = [SerialPortPool]

function _init(gauss::LakeShoreGaussMeter)
	params = gauss.params
	sd = initSerialDevice(gauss, params)
	@info "Connection to LakeShoreGaussMeter established."
	gauss.sd = sd
	setParams(gauss, params)
end

function initSerialDevice(gauss::LakeShoreGaussMeter, params::LakeShoreGaussMeterDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(gauss, sd)
  return sd
end

function initSerialDevice(gauss::LakeShoreGaussMeter, params::LakeShoreGaussMeterPoolParams)
  sd = initSerialDevice(gauss, params.description)
  checkSerialDevice(gauss, sd)
  return sd
end

function setParams(gauss::LakeShoreGaussMeter, params::LakeShoreGaussMeterParams)
	# setStandardSettings(gauss)
	if params.autoRange
		setAllAutoRanging(gauss, '1')
	else
		setAllAutoRanging(gauss, '0')
		setAllRange(gauss, params.range)
	end
	setFast(gauss, params.fast)
	setUnitToTesla(gauss)
	setCompleteProbe(gauss, '0')
end

function checkSerialDevice(gauss::LakeShoreGaussMeter, sd::SerialDevice)
  try
    reply = query(sd, "*IDN?")
    if !(reply == "LSCI,MODEL460,0,032406")
        close(sd)
        throw(ScannerConfigurationError(string("Connected to wrong Device", reply)))
    end
		reply = query(sd, "*TST?")
		if reply != "0"
			close(sd)
			throw(ScannerConfigurationError(string("Errors found in the LakeShoreGaussMeter test: ", reply)))
		end
    return sd
  catch e
    throw(ScannerConfigurationError("Could not verify if connected to correct device"))
  end
end

"""
Returns x,y, and z values and apply a coordinate transformation
"""
function getXYZValues(gauss::LakeShoreGaussMeter)
	field = parse.(Float32,split(getAllFields(gauss),","))[1:3]
	multipliers = getAllMultipliers(gauss)
  return gauss.params.coordinateTransformation*(field.*multipliers)*Unitful.T
end

function getField(gauss::LakeShoreGaussMeter)
	field = "OL"
    while occursin("OL",field)
	  field = query(gauss.sd, "FIELD?")
	  if occursin("OL",field)
        sleep(3.0)
	  end
    end
	return field
end

"""
Returns the field values of X, Y, Z and a fourth reading consiting of
meaningless data.
"""
function getAllFields(gauss::LakeShoreGaussMeter)
	field = "OL,OL,OL,OL"
    while occursin("OL",field)
	  field = query(gauss.sd, "ALLF?")
	  if occursin("OL",field)
        sleep(3.0)
	  end
    end
	return field
end

"""
Returns the state of the field compensation
"""
function isFieldComp(gauss::LakeShoreGaussMeter)
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
function setFieldComp(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "FCOMP $state")
end

function getMultiplier(gauss::LakeShoreGaussMeter)
	res = query(gauss.sd, "FIELDM?")
	if occursin("u",res)
		return 1e-6
	elseif occursin("m",res)
		return 1e-3
	elseif occursin("k",res)
		return 1e3
	else
		return 1.0
	end
end

function getAllMultipliers(gauss::LakeShoreGaussMeter)
	setActiveChannel(gauss, 'X')
	sleep(0.01) # Fynn made me do it
	mx = getMultiplier(gauss)
	setActiveChannel(gauss, 'Y')
	sleep(0.01)
	my = getMultiplier(gauss)
	setActiveChannel(gauss, 'Z')
	sleep(0.01)
	mz = getMultiplier(gauss)
	return [mx,my,mz]
end


"""
Returns the manufacturerID, model number, derial number and firmware revision date
"""
function identification(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "*IDN?")
end

"""
The gaussmeter reports status based on test done at power up. 0 = no erors found, 1= erros found
"""
function selfTest(gauss::LakeShoreGaussMeter)
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
function getMode(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "ACDC?")
end

"""
Set the mode for the channel DC = 0 AC = 1
"""
function setMode(gauss::LakeShoreGaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ACDC $mode")
end

"""
Set the mode of all channels DC = 0, AC = 1
"""
function setAllMode(gauss::LakeShoreGaussMeter, mode::Char)
	setMode(gauss, 'X', mode)
	setMode(gauss, 'Y', mode)
	setMode(gauss, 'Z', mode)
end

"""
Returns the AC Mode RMS = 0, Peak = 1
"""
function getPeakRMS(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "PRMS?")
end

"""
Set the AC mode for the channel RMS = 0, Peak = 1
"""
function setPeakRMS(gauss::LakeShoreGaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "PRMS $mode")
end


"""
Returns the sleep mode status of the gaussmeter
"""
function isInSleepMode(gauss::LakeShoreGaussMeter)
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
function setSleepMode(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "SLEEP $state")
end

"""
Returns the state of the frontpanel lock
"""
function isLocked(gauss::LakeShoreGaussMeter)
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
function getFast(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "FAST?")
end

setFast(gauss::LakeShoreGaussMeter, state::Bool) = setFast(gauss, state ? '1' : '0')
"""
Set fast data command mode.  0 = on, 1 = off
"""
function setFast(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "FAST $state")
end

"""
sets the state of the front panel lock. Locks all entries except the alarm keys. 1 = on, 0 = off
"""
function setFrontPanelLock(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "LOCK $state")
end

"""
Returns the active channel X, Y, Z, V = Vector Magnitude Channel
"""
function getActiveChannel(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "CHNL?")
end

"""
Sets the active channel to X, Y, Z, V = Vector Magnitude Channel
"""
function setActiveChannel(gauss::LakeShoreGaussMeter, channel::Char)
	send(gauss.sd, "CHNL $channel")
end

"""
Returns the active used unit G = gauss, T = tesla
"""
function getUnit(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "UNIT?")
end

"""
Sets the active unit to `'G'` = gauss, `'T'` = tesla
"""
function setUnit(gauss::LakeShoreGaussMeter, unit::Char)
	send(gauss.sd, "UNIT $unit")
end

"""
Returns the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = ±3T
	1           = ±300mT
	2           = ±30mT
	3 = lowest  = ±3mT
"""
function getRange(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "RANGE?")
end

"""
Sets the range of the active channel. The range depends on the installed probe.
For HSE Probe. More Information in part 3.4 on page 3-7.
	0 = highest = ±3T
	1           = ±300mT
	2           = ±30mT
	3 = lowest  = ±3mT
"""
function setRange(gauss::LakeShoreGaussMeter, range::Char)
	send(gauss.sd, "RANGE $range")
end

"""
Returns the state of auto ranging for the active channel
"""
function isAutoRanging(gauss::LakeShoreGaussMeter)
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
function setAutoRanging(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "AUTO $state")
end

"""
Set auto ranging of all channels
"""
function setAllAutoRanging(gauss::LakeShoreGaussMeter, state::Char)
	setActiveChannel(gauss, 'X')
	setAutoRanging(gauss,state)
	setActiveChannel(gauss, 'Y')
	setAutoRanging(gauss,state)
	setActiveChannel(gauss, 'Z')
	setAutoRanging(gauss,state)
end


"""
Returns the state of the probe of the active channel
"""
function isProbeOn(gauss::LakeShoreGaussMeter)
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
function setProbe(gauss::LakeShoreGaussMeter, channel::Char, state::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ONOFF $state")
end

"""
Sets complete probe on = 0 or off = 1
"""
function setCompleteProbe(gauss::LakeShoreGaussMeter, state::Char)
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
function getProbeType(gauss::LakeShoreGaussMeter)
	return query(gauss.sd, "TYPE?")
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

function getFieldError(gauss::LakeShoreGaussMeter, range::Int)
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

function calculateFieldError(gauss::LakeShoreGaussMeter, magneticField::Vector{<:Unitful.BField})
	magneticFieldError = zeros(typeof(1.0u"T"),3,2)
	magneticFieldError[:,1] = abs.(magneticField)*1e-3
	magneticFieldError[:,2] .= getFieldError(gauss, range)
	return sum(magneticFieldError, dims=2)
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


"""
Returns the state of the temperatur compensation
"""
function isTempComp(gauss::LakeShoreGaussMeter)
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
function setTempComp(gauss::LakeShoreGaussMeter, state::Char)
	send(gauss.sd, "TCOMP $state")
end
