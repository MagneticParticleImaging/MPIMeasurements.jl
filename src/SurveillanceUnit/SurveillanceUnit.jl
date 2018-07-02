using Graphics: @mustimplement

export enableACPower, disableACPower, getTemperatures

include("DummySurveillanceUnit.jl")
include("ArduinoSurveillanceUnit.jl")

function SurveillanceUnit(params::Dict)
	if params["type"] == "Dummy"
    return DummySurveillanceUnit()
  elseif params["type"] == "Arduino"
    return ArduinoSurveillanceUnit(params)
  else
    error("Cannot create SurveillanceUnit!")
  end
end

@mustimplement getTemperatures(su::SurveillanceUnit)
@mustimplement enableACPower(su::SurveillanceUnit)
@mustimplement disableACPower(su::SurveillanceUnit)
