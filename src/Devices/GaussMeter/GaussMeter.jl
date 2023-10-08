export GaussMeter
abstract type GaussMeter <: Device end

Base.close(gauss::GaussMeter) = nothing

export getGaussMeters
getGaussMeters(scanner::MPIScanner) = getDevices(scanner, GaussMeter)

export getGaussMeter
getGaussMeter(scanner::MPIScanner) = getDevice(scanner, GaussMeter)

export getCube
getCube(scanner::MPIScanner) = getDevice(scanner,TDesignCube)


export getTemperature
@mustimplement getTemperature(gauss::GaussMeter)

export getFrequency
@mustimplement getFrequency(gauss::GaussMeter)

export calculateFieldError
@mustimplement calculateFieldError(gauss::GaussMeter, magneticField::Vector{<:Unitful.BField})

export getXYZValues
@mustimplement getXYZValues(gauss::GaussMeter)


export getXValue
getXValue(gauss::GaussMeter)=getXYZValues(gauss)[1]

export getYValue
getYValue(gauss::GaussMeter)=getXYZValues(gauss)[2]

export getZValue
getZValue(gauss::GaussMeter)=getXYZValues(gauss)[3]


include("DummyGaussMeter.jl")
include("SimulatedGaussMeter.jl")
include("LakeShore.jl")
include("ArduinoGaussMeter.jl")
include("TDesignCube.jl")
