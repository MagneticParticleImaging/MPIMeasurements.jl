export DummyGaussMeter, DummyGaussMeterParams, getXValue, getYValue, getZValue

Base.@kwdef struct DummyGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
DummyGaussMeterParams(dict::Dict) = params_from_dict(DummyGaussMeterParams, dict)

Base.@kwdef mutable struct DummyGaussMeter <: GaussMeter
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyGaussMeterParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function init(gauss::DummyGaussMeter)
  @info "Initializing dummy gaussmeter unit with ID `$(gauss.deviceID))`."
end

checkDependencies(gauss::DummyGaussMeter) = true

getXValue(gauss::DummyGaussMeter) = 1.0
getYValue(gauss::DummyGaussMeter) = 2.0
getZValue(gauss::DummyGaussMeter) = 3.0
