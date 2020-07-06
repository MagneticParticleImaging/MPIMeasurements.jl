using Graphics: @mustimplement

export getXYZValues

include("DummyGaussMeter.jl")
include("LakeShore.jl")

Base.close(gauss::GaussMeter) = nothing

function GaussMeter(params::Dict)
	if params["type"] == "Dummy"
    return DummyGaussMeter()
  elseif params["type"] == "LakeShore"
    return LakeShoreGaussMeter(params)
  else
    error("Cannot create GaussMeter!")
  end
end

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
