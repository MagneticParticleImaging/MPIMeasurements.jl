export DummyGaussMeter, DummyGaussMeterParams

@option struct DummyGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end

@quasiabstract struct DummyGaussMeter <: GaussMeter
  handle::Union{String, Nothing}

  function DummyGaussMeter(deviceID::String, params::DummyGaussMeterParams)
    return new(deviceID, params, nothing)
  end
end

getXValue(gauss::DummyGaussMeter) = 1.0
getYValue(gauss::DummyGaussMeter) = 2.0
getZValue(gauss::DummyGaussMeter) = 3.0
