using Graphics: @mustimplement

include("DummySurveillanceUnit.jl")
include("ArduinoSurveillanceUnit.jl")

function SurveillanceUnit(params::Dict)
	if params["type"] == "Dummy"
    return DummySurveillanceUnit()
  elseif params["type"] == "Adruino"
    return ArduinoSurveillanceUnit(params)
  else
    error("Cannot create SurveillanceUnit!")
  end
end

@mustimplement getTemperatures(gauss::SurveillanceUnit)
