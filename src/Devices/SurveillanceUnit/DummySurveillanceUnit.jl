export DummySurveillanceUnit, DummySurveillanceUnitParams

@option struct DummySurveillanceUnitParams <: DeviceParams
  
end

@quasiabstract mutable struct DummySurveillanceUnit <: SurveillanceUnit
  acPowerEnabled::Bool

  function DummySurveillanceUnit(deviceID::String, params::DummySurveillanceUnitParams)
    return new(deviceID, params, false)
  end
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