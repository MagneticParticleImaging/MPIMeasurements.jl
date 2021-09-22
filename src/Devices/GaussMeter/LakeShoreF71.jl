export LakeShoreF71GaussMeter, LakeShoreF71GaussMeterParams, LakeShoreF71GaussMeterConnectionModes,
       F71_CM_TCP, F71_CM_USB, F71_MM_AC, F71_MM_DC, F71_MM_HIFR, setMeasurementMode

@enum LakeShoreF71GaussMeterConnectionModes begin
  F71_CM_TCP
  F71_CM_USB
end

function convert(::Type{LakeShoreF71GaussMeterConnectionModes}, x::String)
  if uppercase(x) == "TCP"
    return F71_CM_TCP
  elseif uppercase(x) == "USB"
    return F71_CM_USB
  else
    throw(ScannerConfigurationError("The given connection mode `$x` for the LakeShore F71 gaussmeter is not valid. Please use `TCP` or `USB`."))
  end
end

@enum LakeShoreF71GaussMeterMeasurementModes begin
  F71_MM_DC
  F71_MM_AC
  F71_MM_HIFR
end

function convert(::Type{LakeShoreF71GaussMeterMeasurementModes}, x::String)
  if uppercase(x) == "DC"
    return F71_MM_DC
  elseif uppercase(x) == "AC"
    return F71_MM_AC
  elseif uppercase(x) == "HIFR"
    F71_MM_HIFR
  else
    throw(ScannerConfigurationError("The given measurement mode `$x` for the LakeShore F71 gaussmeter is not valid. Please use `DC`, `AC` or `HIFR`."))
  end
end

# I only add this here until https://github.com/JuliaLang/julia/pull/42272 is decided.
Base.convert(::Type{IPAddr}, str::AbstractString) = parse(IPAddr, str)

Base.@kwdef struct LakeShoreF71GaussMeterParams <: DeviceParams
  connectionMode::LakeShoreF71GaussMeterConnectionModes = F71_CM_USB
  ip::IPAddr = ip"192.168.2.2"
  port::Integer = 7777
  comport::String = "COM4"
  baudrate::Integer = 115200

  measurementMode::LakeShoreF71GaussMeterMeasurementModes = F71_MM_DC

  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
LakeShoreF71GaussMeterParams(dict::Dict) = params_from_dict(LakeShoreF71GaussMeterParams, dict)

"""
 
"""
Base.@kwdef mutable struct LakeShoreF71GaussMeter <: GaussMeter
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::LakeShoreF71GaussMeterParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  driver::Union{SCPIInstrument, Missing} = missing
end

function init(gauss::LakeShoreF71GaussMeter)
  @debug "Initializing LakeShore F71 gaussmeter unit with ID `$(gauss.deviceID)`."
  if gauss.params.connectionMode == F71_CM_TCP
    gauss.driver = TCPSCPIInstrument(gauss.params.ip, gauss.params.port)
  elseif gauss.params.connectionMode == F71_CM_USB
    gauss.driver = SerialSCPIInstrument(gauss.params.comport, gauss.params.baudrate, flow_control=true)
  else
    throw(ScannerConfigurationError("The configured connection mode `$(gauss.params.connectionMode)` is not supported by the LakeShore F71 gaussmeter."))
  end

  setMeasurementMode(gauss, gauss.params.measurementMode)

  # Always use Tesla
  command(gauss.driver, "UNIT:FIELD TESLA")

  gauss.present = true
end

Base.close(gauss::LakeShoreF71GaussMeter) = close(gauss.driver)

ipaddress(gauss::LakeShoreF71GaussMeter) = gauss.params.ip

checkDependencies(gauss::LakeShoreF71GaussMeter) = true

function setMeasurementMode(gauss::LakeShoreF71GaussMeter, mode::LakeShoreF71GaussMeterMeasurementModes)
  if mode == F71_MM_DC
    command(gauss.driver, "SENS:MODE DC")
  elseif mode == F71_MM_AC
    command(gauss.driver, "SENS:MODE AC")
  elseif mode == F71_MM_HIFR
    command(gauss.driver, "SENS:MODE HIFR")
  else
    error("Unsupported measurement mode `$mode`.")
  end
end

getXValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[1]
getYValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[2]
getZValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[3]

function getXYZValues(gauss::LakeShoreF71GaussMeter)
  if gauss.params.measurementMode == F71_MM_DC
    values = parse.(Float64, split(query(gauss.driver, "FETCH:DC? ALL"), ","))[2:4]u"T"
  else
    values = parse.(Float64, split(query(gauss.driver, "FETCH:RMS? ALL"), ","))[2:4]u"T"
  end
  return gauss.params.coordinateTransformation*values
end

getTemperature(gauss::LakeShoreF71GaussMeter) = parse(Float64, query(gauss.driver, "FETCH:TEMP?"))u"°C"

function getFrequency(gauss::LakeShoreF71GaussMeter)
  if gauss.params.measurementMode == F71_MM_DC
    return 0.0u"Hz"
  else
    return parse(Float64, query(gauss.driver, "FETCH:FREQ?"))u"Hz"
  end
end

calculateFieldError(gauss::LakeShoreF71GaussMeter, magneticField::Vector{<:Unitful.BField}) = 0.0u"mT"