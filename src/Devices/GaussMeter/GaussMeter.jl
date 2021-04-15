using Graphics: @mustimplement

export getXYZValues

abstract type GaussMeter <: Device end

include("DummyGaussMeter.jl")
include("LakeShore.jl")

Base.close(gauss::GaussMeter) = nothing

@mustimplement getXValue(gauss::GaussMeter)
@mustimplement getYValue(gauss::GaussMeter)
@mustimplement getZValue(gauss::GaussMeter)

"""
Returns x,y, and z values and apply a coordinate transformation
"""
function getXYZValues(gauss::GaussMeter)
    gauss.coordinateTransformation*[getXValue(gauss),
		 getYValue(gauss),
		 getZValue(gauss)]
end
