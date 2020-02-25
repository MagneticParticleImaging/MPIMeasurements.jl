export TemperatureSensor

include("FOTemp.jl")

function TemperatureSensor(params::Dict)
	if params["type"] == "FOTemp"
    return FOTemp(params)
  else
    error("Cannot create TemperatureSensor!")
  end
end
