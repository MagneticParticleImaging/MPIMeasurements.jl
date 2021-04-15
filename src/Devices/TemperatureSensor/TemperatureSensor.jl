export TemperatureSensor

abstract type TemperatureSensor <: Device end

include("FOTemp.jl")

Base.close(t::TemperatureSensor) = nothing

function TemperatureSensor(params::Dict)
	if params["type"] == "FOTemp"
    return FOTemp(params)
  else
    error("Cannot create TemperatureSensor!")
  end
end
