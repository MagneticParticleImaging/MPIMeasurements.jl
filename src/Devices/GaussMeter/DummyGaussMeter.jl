export DummyGaussMeter, DummyGaussMeterParams, getXValue, getYValue, getZValue

Base.@kwdef struct DummyGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
DummyGaussMeterParams(dict::Dict) = from_dict(DummyGaussMeterParams, dict)

Base.@kwdef mutable struct DummyGaussMeter <: GaussMeter
  deviceID::String
  params::DummyGaussMeterParams
end

getXValue(gauss::DummyGaussMeter) = 1.0
getYValue(gauss::DummyGaussMeter) = 2.0
getZValue(gauss::DummyGaussMeter) = 3.0
