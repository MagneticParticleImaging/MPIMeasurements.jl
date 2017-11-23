export DummySurveillanceUnit

struct DummySurveillanceUnit <: SurveillanceUnit
end


getTemperatures(gauss::DummySurveillanceUnit) = [0.0, 0.0, 0.0, 0.0]
