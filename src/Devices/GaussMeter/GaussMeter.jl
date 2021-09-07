using Graphics: @mustimplement

export GaussMeter, getGaussMeters, getGaussMeter,  getXValue, getYValue, getZValue, getXYZValues, getTemperature, getFrequency

abstract type GaussMeter <: Device end

include("DummyGaussMeter.jl")
include("SimulatedGaussMeter.jl")
#include("LakeShore.jl")
include("LakeShoreF71.jl")

Base.close(gauss::GaussMeter) = nothing

@mustimplement getXValue(gauss::GaussMeter)
@mustimplement getYValue(gauss::GaussMeter)
@mustimplement getZValue(gauss::GaussMeter)
@mustimplement getTemperature(gauss::GaussMeter)
@mustimplement getFrequency(gauss::GaussMeter)
@mustimplement calculateFieldError(gauss::GaussMeter, magneticField::Vector{<:Unitful.BField})

getGaussMeters(scanner::MPIScanner) = getDevices(scanner, GaussMeter)
function getGaussMeter(scanner::MPIScanner)
  gaussMeters = getGaussMeters(scanner)
  if length(gaussMeters) > 1
    error("The scanner has more than one gaussmeter device. Therefore, a single gaussmeter cannot be retrieved unambiguously.")
  else
    return gaussMeters[1]
  end
end

"""
Returns x,y, and z values and applies a coordinate transformation
"""
function getXYZValues(gauss::GaussMeter)
  values = [getXValue(gauss), getYValue(gauss), getZValue(gauss)]
  return gauss.params.coordinateTransformation*values
end
