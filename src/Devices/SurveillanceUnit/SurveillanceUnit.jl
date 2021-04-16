using Graphics: @mustimplement

export enableACPower, disableACPower, getTemperatures, getACStatus, resetDAQ

@quasiabstract struct SurveillanceUnit <: Device end

include("DummySurveillanceUnit.jl")
#include("ArduinoSurveillanceUnit.jl")
#include("ArduinoWithExternalTempUnit.jl")
#include("MPSSurveillanceUnit.jl")

Base.close(su::SurveillanceUnit) = nothing

@mustimplement getTemperatures(su::SurveillanceUnit)
@mustimplement getACStatus(su::SurveillanceUnit, scanner::MPIScanner)
@mustimplement enableACPower(su::SurveillanceUnit, scanner::MPIScanner)
@mustimplement disableACPower(su::SurveillanceUnit, scanner::MPIScanner)
@mustimplement resetDAQ(su::SurveillanceUnit)
