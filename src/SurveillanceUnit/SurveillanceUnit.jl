using Graphics: @mustimplement

export enableACPower, disableACPower, getTemperatures

include("DummySurveillanceUnit.jl")
include("ArduinoSurveillanceUnit.jl")
include("MPSSurveillanceUnit.jl")

function SurveillanceUnit(params::Dict)
	if params["type"] == "Dummy"
    return DummySurveillanceUnit()
  elseif params["type"] == "Arduino"
    return ArduinoSurveillanceUnit(params)
elseif params["type"] == "MPS"
  	return MPSSurveillanceUnit(params)
  else
    error("Cannot create SurveillanceUnit!")
  end
end

@mustimplement getTemperatures(su::SurveillanceUnit)
@mustimplement enableACPower(su::SurveillanceUnit)
@mustimplement disableACPower(su::SurveillanceUnit)
