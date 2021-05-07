using Graphics: @mustimplement

export SurveillanceUnit, getSurveillanceUnits, getSurveillanceUnit, enableACPower, disableACPower, getTemperatures, getACStatus, resetDAQ

abstract type SurveillanceUnit <: Device end

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

getSurveillanceUnits(scanner::MPIScanner) = getDevices(scanner, SurveillanceUnit)
function getSurveillanceUnit(scanner::MPIScanner)
  surveillanceUnits = getSurveillanceUnits(scanner)
  if length(surveillanceUnits) > 1
    error("The scanner has more than one surveillance unit device. Therefore, a single surveillance unit cannot be retrieved unambiguously.")
  else
    return surveillanceUnits[1]
  end
end