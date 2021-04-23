export DummySurveillanceUnit

struct DummySurveillanceUnit <: SurveillanceUnit
end


getTemperatures(su::DummySurveillanceUnit) = 30.0.*ones(4) .+ randn(4)

function enableACPower(su::DummySurveillanceUnit, scanner::MPIScanner)
  @info "Enable AC Power"
end

function disableACPower(su::DummySurveillanceUnit, scanner::MPIScanner)
  @info "Disable AC Power"
end

resetDAQ(su::DummySurveillanceUnit) = nothing