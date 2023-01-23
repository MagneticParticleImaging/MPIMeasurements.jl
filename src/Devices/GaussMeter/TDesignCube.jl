export TDesignCubeParams, TDesignCube, setSampleSize, getSampleSize, getT, getN, getRadius

Base.@kwdef struct TDesignCubeParams <: DeviceParams
    T::Int64
    N::Int64
    radius::typeof(1.0u"mm") = 0.0u"mm"
    sampleSize:: Int64 = 100
end
TDesignCubeParams(dict::Dict) = params_from_dict(TDesignCubeParams, dict)


Base.@kwdef mutable struct TDesignCube <: Device
    @add_device_fields TDesignCubeParams
    sensors::Union{Vector{ArduinoGaussMeter}, Nothing} = nothing
    sampleSize:: Int64 = 100
end

neededDependencies(::TDesignCube) = [ArduinoGaussMeter]
optionalDependencies(::TDesignCube) = []

function _init(cube::TDesignCube)
    sampleSize = cube.params.sampleSize
    sensors = dependencies(cube, ArduinoGaussMeter)
    if length(sensors) != cube.params.N
        close.(sensors) # TODO @NH Should not close devices here
        throw("missing Sensors")
    end
    sort!(sensors,by=x-> x.params.position)
    cube.sensors = sensors
    println(cube.params) # TODO remove
    setSampleSize(cube,cube.sampleSize)
end

export setSampleSize
function setSampleSize(cube::TDesignCube,sampleSize::Int)
    # TODO This check should happen in the sensors, here it should be checked if values could be successfully set, ideally with a bool reply from setSampleSize
    if sampleSize>1024 || sampleSize<1
        throw("sampleSize must be in 1:1024")
    end
    for sensor in cube.sensors
        setSampleSize(sensor,sampleSize)
    end
    cube.sampleSize = sampleSize
end

export getSampleSize
getSampleSize(cube::TDesignCube) = cube.params.sampleSize

function getXYZValues(cube::TDesignCube)
    measurement = zeros(cube.params.T,6)
    #triggerMeasurment
    for sensor in cube.sensors
        triggerMeasurment(sensor)
    end
    #readmeasurement
    for (i,sensor) in enumerate(cube.sensors)
        measurement[i,:] = reciveMeasurment(sensor)
    end
    return measurement
end

getT(cube::TDesignCube) = cube.params.T
getN(cube::TDesignCube) = cube.params.N
getRadius(cube::TDesignCube) = cube.params.radius

function close(cube::TDesignCube)
    # NOP
end 