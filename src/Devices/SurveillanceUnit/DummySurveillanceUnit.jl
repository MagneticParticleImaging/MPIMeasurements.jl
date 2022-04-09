export DummySurveillanceUnit, DummySurveillanceUnitParams

Base.@kwdef struct DummySurveillanceUnitParams <: DeviceParams

end
DummySurveillanceUnitParams(dict::Dict) = params_from_dict(DummySurveillanceUnitParams, dict)

Base.@kwdef mutable struct DummySurveillanceUnit <: SurveillanceUnit
  @add_device_fields DummySurveillanceUnitParams

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
