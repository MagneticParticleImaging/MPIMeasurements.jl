export DummySurveillanceUnit, DummySurveillanceUnitParams

Base.@kwdef struct DummySurveillanceUnitParams <: DeviceParams

end
DummySurveillanceUnitParams(dict::Dict) = params_from_dict(DummySurveillanceUnitParams, dict)

Base.@kwdef mutable struct DummySurveillanceUnit <: SurveillanceUnit
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummySurveillanceUnitParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  acPowerEnabled::Bool = false
end

function _init(su::DummySurveillanceUnit)
  # NOP
end

neededDependencies(::DummySurveillanceUnit) = []
optionalDependencies(::DummySurveillanceUnit) = []

Base.close(su::DummySurveillanceUnit) = nothing

getTemperatures(su::DummySurveillanceUnit) = 30.0.*ones(4) .+ 1.0.*randn(4)
getACStatus(su::DummySurveillanceUnit) = su.acPowerEnabled

function enableACPower(su::DummySurveillanceUnit)
  @debug "Enable AC Power"
  su.acPowerEnabled = true
end

function disableACPower(su::DummySurveillanceUnit)
  @debug "Disable AC Power"
  su.acPowerEnabled = false
end


resetDAQ(su::DummySurveillanceUnit) = nothing
hasResetDAQ(su::DummySurveillanceUnit) = false
