export DummyGaussMeter, DummyGaussMeterParams

Base.@kwdef struct DummyGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
DummyGaussMeterParams(dict::Dict) = params_from_dict(DummyGaussMeterParams, dict)

Base.@kwdef mutable struct DummyGaussMeter <: GaussMeter
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyGaussMeterParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function _init(gauss::DummyGaussMeter)
  # NOP
end

neededDependencies(::DummyGaussMeter) = []
optionalDependencies(::DummyGaussMeter) = []

Base.close(gauss::DummyGaussMeter) = nothing

getXValue(gauss::DummyGaussMeter) = 1.0u"mT"
getYValue(gauss::DummyGaussMeter) = 2.0u"mT"
getZValue(gauss::DummyGaussMeter) = 3.0u"mT"
getTemperature(gauss::DummyGaussMeter) = 20.0u"°C"
getFrequency(gauss::DummyGaussMeter) = 0.0u"Hz"
calculateFieldError(gauss::DummyGaussMeter, magneticField::Vector{<:Unitful.BField}) = 1.0u"mT"