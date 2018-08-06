export DummySurveillanceUnit

struct DummySurveillanceUnit <: SurveillanceUnit
end


getTemperatures(su::DummySurveillanceUnit) = 30.0.*ones(4) .+ randn(4)

function enableACPower(su::DummySurveillanceUnit)
  println("Enable AC Power")
end

function disableACPower(su::DummySurveillanceUnit)
  println("Disable AC Power")
end
