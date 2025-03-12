export DummyFieldCamera, DummyFieldCameraParams

Base.@kwdef struct DummyFieldCameraParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
  string::String
end
DummyFieldCameraParams(dict::Dict) = params_from_dict(DummyFieldCameraParams, dict)

Base.@kwdef mutable struct DummyFieldCamera <: AbstractFieldCamera
  @add_device_fields DummyFieldCameraParams
end

function _init(gauss::DummyFieldCamera)
  # NOP
end

neededDependencies(::DummyFieldCamera) = []
optionalDependencies(::DummyFieldCamera) = []

getXYZValues(::DummyFieldCamera) = rand(3, 86, 1)
tDesignParameter(::DummyFieldCamera) = 12, 86, [0.0, 0.0, 0.0], 0.045

Base.close(gauss::DummyFieldCamera) = nothing

