using Graphics: @mustimplement

export enableACPower, disableACPower, getTemperatures, resetDAQ

abstract type SurveillanceUnit <: Device end

include("DummySurveillanceUnit.jl")
include("ArduinoSurveillanceUnit.jl")
include("ArduinoWithExternalTempUnit.jl")
include("MPSSurveillanceUnit.jl")

Base.close(su::SurveillanceUnit) = nothing

function SurveillanceUnit(params::Dict)
	if params["type"] == "Dummy"
    return DummySurveillanceUnit()
  elseif params["type"] == "Arduino"
    return ArduinoSurveillanceUnit(params)
  elseif params["type"] == "ArduinoWithExternalTempUnit"
    return ArduinoWithExternalTempUnit(params)
  elseif params["type"] == "MPS"
  	return MPSSurveillanceUnit(params)
  else
    error("Cannot create SurveillanceUnit!")
  end
end

@mustimplement getTemperatures(su::SurveillanceUnit)
@mustimplement enableACPower(su::SurveillanceUnit, scanner::MPIScanner)
@mustimplement disableACPower(su::SurveillanceUnit, scanner::MPIScanner)
@mustimplement resetDAQ(su::SurveillanceUnit)
