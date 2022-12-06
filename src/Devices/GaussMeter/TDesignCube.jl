
#=export TDesignCubeParams, TDesignCube

Base.@kwdef struct TDesignCubeParams <: DeviceParams
    T::Int64
    N::Int64
    radius::typeof(1.0u"mm") = 0.0u"mm"
end

Base.@kwdef mutable struct TDesignCube <: Device
    @add_device_fields TDesignCubeParams
    sensors::Union{Vector{ArduinoGaussMeter}, Nothing} = nothing
end

neededDependencies(::ArduinoGaussMeter) = [ArduinoGaussMeter]
optionalDependencies(::ArduinoGaussMeter) = []

function _init(cube::TDesignCube)
    sensors = dependencies(cube, ArduinoGaussMeter)
    # TODO Check if all needed sensors are there if not throw ScannerConfigurationError
    # TODO Sort sensors according to position
    cube.sensors = sensors
end

# TODO get/setSampleSizes

function getXYZValues(cube::TDesignCube)
    measurement = zeros(typeof(u"T"), 3, cube.params.T)
    # TODO Implement this with start/receive from sensors
    return measurement
end

# TODO implement "getters" for T, N, radius

function close(cube::TDesignCube)
    # NOP
end 
=#