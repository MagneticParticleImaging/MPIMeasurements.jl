using Graphics: @mustimplement

export GaussMeter, getGaussMeters, getGaussMeter,  getXValue, getYValue, getZValue, getXYZValues

@quasiabstract struct GaussMeter <: Device end

include("DummyGaussMeter.jl")
#include("LakeShore.jl")

Base.close(gauss::GaussMeter) = nothing

@mustimplement getXValue(gauss::GaussMeter)
@mustimplement getYValue(gauss::GaussMeter)
@mustimplement getZValue(gauss::GaussMeter)

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
Returns x,y, and z values and apply a coordinate transformation
"""
function getXYZValues(gauss::GaussMeter)
  gauss.params.coordinateTransformation*[getXValue(gauss),
  getYValue(gauss),
  getZValue(gauss)]
end
