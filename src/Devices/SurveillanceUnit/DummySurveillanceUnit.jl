export DummySurveillanceUnit, DummySurveillanceUnitParams

Base.@kwdef struct DummySurveillanceUnitParams <: DeviceParams
  
end
DummySurveillanceUnitParams(dict::Dict) = from_dict(DummySurveillanceUnitParams, dict)

Base.@kwdef mutable struct DummySurveillanceUnit <: SurveillanceUnit
  deviceID::String
  params::DummySurveillanceUnitParams
  acPowerEnabled::Bool = false
end

getTemperatures(su::DummySurveillanceUnit) = 30.0u"°C"

getACStatus(su::DummySurveillanceUnit, scanner::MPIScanner) = su.acPowerEnabled

function enableACPower(su::DummySurveillanceUnit, scanner::MPIScanner)
  @debug "Enable AC Power"
  su.acPowerEnabled = true
end

function disableACPower(su::DummySurveillanceUnit, scanner::MPIScanner)
  @debug "Disable AC Power"
  su.acPowerEnabled = false
end

resetDAQ(su::DummySurveillanceUnit) = nothing