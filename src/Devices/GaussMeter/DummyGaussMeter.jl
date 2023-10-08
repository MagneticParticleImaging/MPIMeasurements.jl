export DummyGaussMeter, DummyGaussMeterParams

Base.@kwdef struct DummyGaussMeterParams <: DeviceParams
  positionID = 0
end
DummyGaussMeterParams(dict::Dict) = params_from_dict(DummyGaussMeterParams, dict)

Base.@kwdef mutable struct DummyGaussMeter <: GaussMeter
  @add_device_fields DummyGaussMeterParams
end

function _init(gauss::DummyGaussMeter)
  # NOP
end

neededDependencies(::DummyGaussMeter) = []
optionalDependencies(::DummyGaussMeter) = []

Base.close(gauss::DummyGaussMeter) = nothing
function triggerMeasurment(gauss::DummyGaussMeter) 
  #NOP
end
receiveMeasurment(gauss::DummyGaussMeter) =getXYZValues(gauss)
setSampleSize(gauss::DummyGaussMeter, sampleSize) = sampleSize
getXYZValue(gauss::DummyGaussMeter) = [1.0,u"mT",2.0u"mT",3.0u"mT"]
getTemperature(gauss::DummyGaussMeter) = 20.0u"°C"
getFrequency(gauss::DummyGaussMeter) = 0.0u"Hz"
calculateFieldError(gauss::DummyGaussMeter, magneticField::Vector{<:Unitful.BField}) = 1.0u"mT"