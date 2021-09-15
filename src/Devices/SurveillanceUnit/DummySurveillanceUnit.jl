export DummySurveillanceUnit, DummySurveillanceUnitParams

Base.@kwdef struct DummySurveillanceUnitParams <: DeviceParams
  
end
DummySurveillanceUnitParams(dict::Dict) = params_from_dict(DummySurveillanceUnitParams, dict)

Base.@kwdef mutable struct DummySurveillanceUnit <: SurveillanceUnit
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummySurveillanceUnitParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  acPowerEnabled::Bool = false
end

function init(su::DummySurveillanceUnit)
  @debug "Initializing dummy surveillance unit with ID `$(su.deviceID)`."
end

checkDependencies(su::DummySurveillanceUnit) = true

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
hasResetDAQ(su::DummySurveillanceUnit) = false