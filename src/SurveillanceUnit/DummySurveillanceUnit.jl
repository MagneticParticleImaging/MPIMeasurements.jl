export DummySurveillanceUnit

struct DummySurveillanceUnit <: SurveillanceUnit
end


getTemperatures(su::DummySurveillanceUnit) = 30.0.*ones(4) .+ randn(4)

function enableACPower(su::DummySurveillanceUnit)
  @info "Enable AC Power"
end

function disableACPower(su::DummySurveillanceUnit)
  @info "Disable AC Power"
end
