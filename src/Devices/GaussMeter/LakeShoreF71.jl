using Sockets
using PyCall

export LakeShoreF71GaussMeter, LakeShoreF71GaussMeterParams, getXValue, getYValue, getZValue

# @enum LakeShoreF71GaussMeterModes

# end

Base.@kwdef struct LakeShoreF71GaussMeterParams <: DeviceParams
  ip::IPAddr = ip"192.168.2.2"
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  #mode::
end
LakeShoreF71GaussMeterParams(dict::Dict) = params_from_dict(LakeShoreF71GaussMeterParams, dict)

Base.@kwdef mutable struct LakeShoreF71GaussMeter <: GaussMeter
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::LakeShoreF71GaussMeterParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  driver = missing
end

function init(gauss::LakeShoreF71GaussMeter)
  @info "Initializing simulated gaussmeter unit with ID `$(gauss.deviceID)`."
  fromLakeshore = PyCall.pyimport("lakeshore")
  gauss.driver = fromLakeshore.Teslameter(ip_address=ipaddress(gauss))
end

ipaddress(gauss::LakeShoreF71GaussMeter) = gauss.params.ip

checkDependencies(gauss::LakeShoreF71GaussMeter) = true

getXValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[1]
getYValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[2]
getZValue(gauss::LakeShoreF71GaussMeter) = getXYZValues(gauss)[3]
getXYZValues(gauss::GaussMeter) = gauss.driver.get_rms_field_xyz()u"T"
getTemperature(gauss::LakeShoreF71GaussMeter) = gauss.driver.get_temperature()u"°C"
getFrequency(gauss::LakeShoreF71GaussMeter) = gauss.driver.get_frequency()u"Hz"
calculateFieldError(gauss::LakeShoreF71GaussMeter, magneticField::Vector{<:Unitful.BField}) = 0.0u"mT"