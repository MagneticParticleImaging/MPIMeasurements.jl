export SimulatedGaussMeter, SimulatedGaussMeterParams, getXValue, getYValue, getZValue

Base.@kwdef struct SimulatedGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
SimulatedGaussMeterParams(dict::Dict) = params_from_dict(SimulatedGaussMeterParams, dict)

Base.@kwdef mutable struct SimulatedGaussMeter <: GaussMeter
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedGaussMeterParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function _init(gauss::SimulatedGaussMeter)
  # NOP
end

neededDependencies(::SimulatedGaussMeter) = []
optionalDependencies(::SimulatedGaussMeter) = []

Base.close(gauss::SimulatedGaussMeter) = nothing

getXValue(gauss::SimulatedGaussMeter) = 1.0u"mT"
getYValue(gauss::SimulatedGaussMeter) = 2.0u"mT"
getZValue(gauss::SimulatedGaussMeter) = 3.0u"mT"
getTemperature(gauss::SimulatedGaussMeter) = 20.0u"°C"
getFrequency(gauss::SimulatedGaussMeter) = 0.0u"Hz"
calculateFieldError(gauss::SimulatedGaussMeter, magneticField::Vector{<:Unitful.BField}) = 1.0u"mT"