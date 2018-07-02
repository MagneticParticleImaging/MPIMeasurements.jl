export DummySurveillanceUnit

struct DummySurveillanceUnit <: SurveillanceUnit
end


getTemperatures(su::DummySurveillanceUnit) = [0.0, 0.0, 0.0, 0.0]

function enableACPower(su::DummySurveillanceUnit)
  println("Enable AC Power")
end

function disableACPower(su::DummySurveillanceUnit)
  println("Disable AC Power")
end
