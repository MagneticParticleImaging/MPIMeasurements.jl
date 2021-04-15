export DummyGaussMeter

@option struct DummyGaussMeter <: GaussMeter
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end

getXValue(gauss::DummyGaussMeter) = 1.0
getYValue(gauss::DummyGaussMeter) = 2.0
getZValue(gauss::DummyGaussMeter) = 3.0
