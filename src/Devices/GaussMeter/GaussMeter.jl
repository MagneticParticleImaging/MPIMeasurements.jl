export GaussMeter
abstract type GaussMeter <: Device end

Base.close(gauss::GaussMeter) = nothing

export getGaussMeters
getGaussMeters(scanner::MPIScanner) = getDevices(scanner, GaussMeter)

export getGaussMeter
getGaussMeter(scanner::MPIScanner) = getDevice(scanner, GaussMeter)

export getXValue
@mustimplement getXValue(gauss::GaussMeter)

export getYValue
@mustimplement getYValue(gauss::GaussMeter)

export getZValue
@mustimplement getZValue(gauss::GaussMeter)

export getTemperature
@mustimplement getTemperature(gauss::GaussMeter)

export getFrequency
@mustimplement getFrequency(gauss::GaussMeter)

export calculateFieldError
@mustimplement calculateFieldError(gauss::GaussMeter, magneticField::Vector{<:Unitful.BField})

export getXYZValues
"""
Returns x,y, and z values and applies a coordinate transformation
"""
function getXYZValues(gauss::GaussMeter)
  values = [getXValue(gauss), getYValue(gauss), getZValue(gauss)]
  return gauss.params.coordinateTransformation*values
end

include("DummyGaussMeter.jl")
include("SimulatedGaussMeter.jl")
include("LakeShore.jl")
include("ArduinoGaussMeter.jl")
include("TDesginCube.jl")
