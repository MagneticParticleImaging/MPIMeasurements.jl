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
    setSampleSize(cube,cube.sampleSize)
end

export setSampleSize
function setSampleSize(cube::TDesignCube,sampleSize::Int)
    for sensor in cube.sensors
        returnSampleSize = setSampleSize(sensor,sampleSize)
        if returnSampleSize != sampleSize
            throw("sensors coud not be updated") 
        end
    end
    cube.sampleSize = sampleSize
end

export getSampleSize
getSampleSize(cube::TDesignCube) = cube.params.sampleSize

function getXYZValues(cube::TDesignCube)
    measurement = zeros(cube.params.N,3)
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