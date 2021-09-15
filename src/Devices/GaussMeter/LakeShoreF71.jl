using Sockets
using SCPIInstruments

export LakeShoreF71GaussMeter, LakeShoreF71GaussMeterParams, LakeShoreF71GaussMeterConnectionModes,
       F71_CM_TCP, F71_CM_USB, F71_MM_AC, F71_MM_DC, F71_MM_HIFR

@enum LakeShoreF71GaussMeterConnectionModes begin
  F71_CM_TCP
  F71_CM_USB
end

@enum LakeShoreF71GaussMeterMeasurementModes begin
  F71_MM_DC
  F71_MM_AC
  F71_MM_HIFR
end

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
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  driver::Union{SCPIInstrument, Missing} = missing
end

function init(gauss::LakeShoreF71GaussMeter)
  @debug "Initializing LakShore F71 gaussmeter unit with ID `$(gauss.deviceID)`."
  if gauss.params.connectionMode == F71_CM_TCP
    gauss.driver = TCPSCPIInstrument(gauss.params.ip, gauss.params.port)
  elseif gauss.params.connectionMode == F71_CM_USB
    gauss.driver = SerialSCPIInstrument(gauss.params.comport, gauss.params.baudrate, flow_control=true)
  end

  setMeasurementMode(gauss, gauss.params.measurementMode)

  # Always use Tesla
  command(gauss.driver, "UNIT:FIELD TESLA")
end

Base.close(gauss::LakeShoreF71GaussMeter) = close(gauss.driver)

ipaddress(gauss::LakeShoreF71GaussMeter) = gauss.params.ip

checkDependencies(gauss::LakeShoreF71GaussMeter) = true

function setMeasurementMode(gauss::LakeShoreF71GaussMeter, mode::LakeShoreF71GaussMeterMeasurementModes)
  if mode == F71_MM_DC
    SCPIInstruments.command(gauss.driver, "SENS:MODE DC")
  elseif mode == F71_MM_AC
    SCPIInstruments.command(gauss.driver, "SENS:MODE AC")
  elseif mode == F71_MM_HIFR
    SCPIInstruments.command(gauss.driver, "SENS:MODE HIFR")
  else
    error("Unsupported measurement mode `$mode`.")
  end
end

getXValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[1]
getYValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[2]
getZValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[3]

function getXYZValues(gauss::LakeShoreF71GaussMeter)
  if gauss.params.measurementMode == F71_MM_DC
    values = parse.(Float64, split(SCPIInstruments.query(gauss.driver, "FETCH:DC? ALL"), ","))[2:4]u"T"
  else
    values = parse.(Float64, split(SCPIInstruments.query(gauss.driver, "FETCH:RMS? ALL"), ","))[2:4]u"T"
  end
  return gauss.params.coordinateTransformation*values
end

getTemperature(gauss::LakeShoreF71GaussMeter) = parse(Float64, SCPIInstruments.query(gauss.driver, "FETCH:TEMP?"))u"°C"

function getFrequency(gauss::LakeShoreF71GaussMeter)
  if gauss.params.measurementMode == F71_MM_DC
    return 0.0u"Hz"
  else
    return parse(Float64, SCPIInstruments.query(gauss.driver, "FETCH:FREQ?"))u"Hz"
  end
end

calculateFieldError(gauss::LakeShoreF71GaussMeter, magneticField::Vector{<:Unitful.BField}) = 0.0u"mT"