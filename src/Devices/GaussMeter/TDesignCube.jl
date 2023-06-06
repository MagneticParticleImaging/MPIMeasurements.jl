export TDesignCubeParams, TDesignCube, setSampleSize, getSampleSize, getT, getN, getRadius, getPositions, getTemperature, measurment

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
    sort!(sensors,by=x-> x.params.positionID)
    cube.sensors = sensors
    setSampleSize(cube,sampleSize)
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
getSampleSize(cube::TDesignCube) = cube.sampleSize

function getXYZValues(cube::TDesignCube)
    measurement = zeros(3,cube.params.N)
    #triggerMeasurment
    for sensor in cube.sensors
        triggerMeasurment(sensor)
    end
    #readmeasurement
    for (i,sensor) in enumerate(cube.sensors)
        measurement[:,i] = receiveMeasurment(sensor)
    end
    return measurement
end

getT(cube::TDesignCube) = cube.params.T
getN(cube::TDesignCube) = cube.params.N
getRadius(cube::TDesignCube) = cube.params.radius

function getPositions(cube::TDesignCube)
    positions = zeros(cube.params.N,3)
    for (i,sensor) in enumerate(cube.sensors)
        positions[i,:] = getPosition(sensor)
    end
    return positions
end

function getTemperatures(cube::TDesignCube)
    temperatures = zeros(cube.params.N)
    for (i,sensor) in enumerate(cube.sensors)
        temperatures[i] = getTemperature(sensor)
    end
    return temperatures
end

#starts measument and stores it into a hdf5 file
function measurment(cube,filename,center_position=[0,0,0],sampleSize=1000)
    setSampleSize(cube,1000)
    data = getXYZValues(cube)
    println(data)
    h5open(filename, "w") do file
        println("hear")
        write(file,"/fields", data) 		# measured field (size: 3 x #points x #patches)
        println("hear2")
        println(cube.params.radius)
        write(file,"/positions/tDesign/radius", ustrip(u"m",cube.params.radius))	# radius of the measured ball
        write(file,"/positions/tDesign/N", cube.params.N)		# number of points of the t-design
        write(file,"/positions/tDesign/t", cube.params.T)		# t of the t-design
        write(file,"/positions/tDesign/center", center_position)	# center of the measured ball
      end
      return measurement
    end

function close(cube::TDesignCube)
    #NOP
end 