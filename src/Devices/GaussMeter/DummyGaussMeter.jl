export DummyGaussMeter, DummyGaussMeterParams, getXValue, getYValue, getZValue

@option struct DummyGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end

@quasiabstract mutable struct DummyGaussMeter <: GaussMeter

  function DummyGaussMeter(deviceID::String, params::DummyGaussMeterParams)
    return new(deviceID, params)
  end
end

getXValue(gauss::DummyGaussMeter) = 1.0
getYValue(gauss::DummyGaussMeter) = 2.0
getZValue(gauss::DummyGaussMeter) = 3.0
