export setAllRange
export sleepModeOn,sleepModeOff,lockOn,lockOff
export setUnitToTesla,setStandardSettings, getFieldError, calculateFieldError

export LakeShore460GaussMeterDirectParams, LakeShore460GaussMeterPoolParams, LakeShore460GaussMeter, LakeShore460GaussMeterParams

struct CachedMultiplier end
struct LiveMultiplier end

abstract type LakeShore460GaussMeterParams <: DeviceParams end

Base.@kwdef struct LakeShore460GaussMeterDirectParams <: LakeShore460GaussMeterParams
	portAddress::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
	sensorCorrectionTranslation::Matrix{Float64} = zeros(Float64, 3, 3) 
	autoRange::Bool = true
	range::Int64 = 3
	completeProbe::Char = '1'
	fast::Bool = true
	@add_serial_device_fields "\r\n" 7 SP_PARITY_ODD
end
function LakeShore460GaussMeterDirectParams(dict::Dict) 
	if haskey(dict, "coordinateTransformation")
		dict["coordinateTransformation"] = reshape(dict["coordinateTransformation"], 3, 3)
	end
	params_from_dict(LakeShore460GaussMeterDirectParams, dict)
end

Base.@kwdef struct LakeShore460GaussMeterPoolParams <: LakeShore460GaussMeterParams
	description::String
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
	sensorCorrectionTranslation::Matrix{Float64} = zeros(Float64, 3, 3)
	autoRange::Bool = true
	range::Int64 = 3
	completeProbe::Char = '1'
	fast::Bool = true
	@add_serial_device_fields "\r\n" 7 SP_PARITY_ODD
end
function LakeShore460GaussMeterPoolParams(dict::Dict) 
	if haskey(dict, "coordinateTransformation")
		dict["coordinateTransformation"] = reshape(dict["coordinateTransformation"], 3, 3)
	end
	params_from_dict(LakeShore460GaussMeterPoolParams, dict)
end

Base.@kwdef mutable struct LakeShore460GaussMeter <: GaussMeter
	@add_device_fields LakeShore460GaussMeterParams
	multiplier::Union{Vector{Float64}, Nothing} = nothing
	sd::Union{SerialDevice, Nothing} = nothing
end

neededDependencies(::LakeShore460GaussMeter) = []
optionalDependencies(::LakeShore460GaussMeter) = [SerialPortPool]

function _init(gauss::LakeShore460GaussMeter)
	params = gauss.params
	sd = initSerialDevice(gauss, params)
	@info "Connection to LakeShoreGaussMeter established."
	gauss.sd = sd
	setParams(gauss, params)
end

function initSerialDevice(gauss::LakeShore460GaussMeter, params::LakeShore460GaussMeterDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  checkSerialDevice(gauss, sd)
  return sd
end

function initSerialDevice(gauss::LakeShore460GaussMeter, params::LakeShore460GaussMeterPoolParams)
  sd = initSerialDevice(gauss, params.description)
  checkSerialDevice(gauss, sd)
  return sd
end

function setParams(gauss::LakeShore460GaussMeter, params::LakeShore460GaussMeterParams)
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

function checkSerialDevice(gauss::LakeShore460GaussMeter, sd::SerialDevice)
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
function getXYZValues(gauss::LakeShore460GaussMeter)
	field = parse.(Float32,split(getAllFields(gauss),","))[1:3]
	multipliers = getAllMultipliers(gauss, LiveMultiplier()) # Caching has a race condition/weird behaviour
  return gauss.params.coordinateTransformation*(field.*multipliers)*Unitful.T
end

function getField(gauss::LakeShore460GaussMeter)
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
function getAllFields(gauss::LakeShore460GaussMeter)
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
function isFieldComp(gauss::LakeShore460GaussMeter)
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
function setFieldComp(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "FCOMP $state")
end

function getMultiplier(gauss::LakeShore460GaussMeter)
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

function getAllMultipliers(gauss::LakeShore460GaussMeter, ::LiveMultiplier)
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

function getAllMultipliers(gauss::LakeShore460GaussMeter, ::CachedMultiplier)
	if isnothing(gauss.multiplier)
		gauss.multiplier = getAllMultipliers(gauss, LiveMultiplier())
	end
	return gauss.multiplier
end

function getAllMultipliers(gauss::LakeShore460GaussMeter)
	type = gauss.params.autoRange ? LiveMultiplier() : CachedMultiplier()
	return getAllMultipliers(gauss, type)
end

"""
Returns the manufacturerID, model number, derial number and firmware revision date
"""
function identification(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "*IDN?")
end

"""
The gaussmeter reports status based on test done at power up. 0 = no erors found, 1= erros found
"""
function selfTest(gauss::LakeShore460GaussMeter)
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
function getMode(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "ACDC?")
end

"""
Set the mode for the channel DC = 0 AC = 1
"""
function setMode(gauss::LakeShore460GaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ACDC $mode")
end

"""
Set the mode of all channels DC = 0, AC = 1
"""
function setAllMode(gauss::LakeShore460GaussMeter, mode::Char)
	setMode(gauss, 'X', mode)
	setMode(gauss, 'Y', mode)
	setMode(gauss, 'Z', mode)
end

"""
Returns the AC Mode RMS = 0, Peak = 1
"""
function getPeakRMS(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "PRMS?")
end

"""
Set the AC mode for the channel RMS = 0, Peak = 1
"""
function setPeakRMS(gauss::LakeShore460GaussMeter, channel::Char, mode::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "PRMS $mode")
end


"""
Returns the sleep mode status of the gaussmeter
"""
function isInSleepMode(gauss::LakeShore460GaussMeter)
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
function setSleepMode(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "SLEEP $state")
end

"""
Returns the state of the frontpanel lock
"""
function isLocked(gauss::LakeShore460GaussMeter)
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
function getFast(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "FAST?")
end

setFast(gauss::LakeShore460GaussMeter, state::Bool) = setFast(gauss, state ? '1' : '0')
"""
Set fast data command mode.  0 = on, 1 = off
"""
function setFast(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "FAST $state")
end

"""
sets the state of the front panel lock. Locks all entries except the alarm keys. 1 = on, 0 = off
"""
function setFrontPanelLock(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "LOCK $state")
end

"""
Returns the active channel X, Y, Z, V = Vector Magnitude Channel
"""
function getActiveChannel(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "CHNL?")
end

"""
Sets the active channel to X, Y, Z, V = Vector Magnitude Channel
"""
function setActiveChannel(gauss::LakeShore460GaussMeter, channel::Char)
	send(gauss.sd, "CHNL $channel")
end

"""
Returns the active used unit G = gauss, T = tesla
"""
function getUnit(gauss::LakeShore460GaussMeter)
	return query(gauss.sd, "UNIT?")
end

"""
Sets the active unit to `'G'` = gauss, `'T'` = tesla
"""
function setUnit(gauss::LakeShore460GaussMeter, unit::Char)
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
function getRange(gauss::LakeShore460GaussMeter)
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
function setRange(gauss::LakeShore460GaussMeter, range::Int64)
	send(gauss.sd, "RANGE $range")
end

"""
Returns the state of auto ranging for the active channel
"""
function isAutoRanging(gauss::LakeShore460GaussMeter)
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
function setAutoRanging(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "AUTO $state")
end

"""
Set auto ranging of all channels
"""
function setAllAutoRanging(gauss::LakeShore460GaussMeter, state::Char)
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
function isProbeOn(gauss::LakeShore460GaussMeter)
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
function setProbe(gauss::LakeShore460GaussMeter, channel::Char, state::Char)
	setActiveChannel(gauss, channel)
	send(gauss.sd, "ONOFF $state")
end

"""
Sets complete probe on = 0 or off = 1
"""
function setCompleteProbe(gauss::LakeShore460GaussMeter, state::Char)
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
function getProbeType(gauss::LakeShore460GaussMeter)
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
setXRange(gauss::LakeShore460GaussMeter, range::Int64) = setRange(gauss, 'X', range, 1)

"""
Sets the range of the Y channel
"""
setYRange(gauss::LakeShore460GaussMeter, range::Int64) = setRange(gauss, 'Y', range, 2)

"""
Sets the range of the Z channel
"""
setZRange(gauss::LakeShore460GaussMeter, range::Int64) = setRange(gauss, 'Z', range, 3)


function setRange(gauss::LakeShore460GaussMeter, channel::Char, range::Int64, index::Int64)
	setActiveChannel(gauss, channel)
	sleep(0.05)
	setRange(gauss, range)
	sleep(0.05)
	if isnothing(gauss.multiplier)
		gauss.multiplier = zeros(Float64, 3)
	end
	sleep(0.05)
	gauss.multiplier[index] = getMultiplier(gauss)
end

"""
Sets the range of all channels
"""
function setAllRange(gauss::LakeShore460GaussMeter, range::Int64)
	setXRange(gauss, range)
	setYRange(gauss, range)
	setZRange(gauss, range)
	return nothing
end

function getFieldError(gauss::LakeShore460GaussMeter, range::Int64)
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

function calculateFieldError(gauss::LakeShore460GaussMeter, magneticField::Vector{<:Unitful.BField})
	magneticFieldError = zeros(typeof(1.0u"T"),3,2)
	magneticFieldError[:,1] = abs.(magneticField)*1e-3
	magneticFieldError[:,2] .= getFieldError(gauss, tryparse(Int64, string(gauss.params.range)))
	return sum(magneticFieldError, dims=2)
end

"""
Sets the sleep mode on
"""
function sleepModeOn(gauss::LakeShore460GaussMeter)
	setSleepMode(gauss, '0')
	return nothing
end

"""
Sets the sleep mode off
"""
function sleepModeOff(gauss::LakeShore460GaussMeter)
	setSleepMode(gauss, '1')
	return nothing
end

"""
Locks the frontpanel
"""
function lockOn(gauss::LakeShore460GaussMeter)
	setFrontPanelLock(gauss, '1')
	return nothing
end

"""
Unlocks the frontpanel
"""
function lockOff(gauss::LakeShore460GaussMeter)
	setFrontPanelLock(gauss, '0')
	return nothing
end

"""
Sets the unit of the values to gauss
"""
function setUnitToGauss(gauss::LakeShore460GaussMeter)
	setUnit(gauss, 'G')
	return nothing
end

"""
Sets the unit of the values to tesla
"""
function setUnitToTesla(gauss::LakeShore460GaussMeter)
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
function setStandardSettings(gauss::LakeShore460GaussMeter)
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
function isTempComp(gauss::LakeShore460GaussMeter)
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
function setTempComp(gauss::LakeShore460GaussMeter, state::Char)
	send(gauss.sd, "TCOMP $state")
end

close(gauss::LakeShore460GaussMeter) = close(gauss.sd)