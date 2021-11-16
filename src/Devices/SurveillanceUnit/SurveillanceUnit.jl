using Graphics: @mustimplement

export SurveillanceUnit, getSurveillanceUnits, getSurveillanceUnit, enableACPower, disableACPower, getTemperatures, getACStatus, resetDAQ

abstract type SurveillanceUnit <: Device end

include("DummySurveillanceUnit.jl")
include("ArduinoSurveillanceUnit.jl")
include("ArduinoSurveillanceUnitExternalTemp.jl")
include("ArduinoSurveillanceUnitInternalTemp.jl")
#include("MPSSurveillanceUnit.jl") TODO

Base.close(su::SurveillanceUnit) = nothing

@mustimplement getTemperatures(su::SurveillanceUnit)
@mustimplement getACStatus(su::SurveillanceUnit)
@mustimplement enableACPower(su::SurveillanceUnit)
@mustimplement disableACPower(su::SurveillanceUnit)
@mustimplement resetDAQ(su::SurveillanceUnit)
@mustimplement hasResetDAQ(su::SurveillanceUnit) # TODO is this has as in "was reset successfull" or if it has the ability to do so?

getSurveillanceUnits(scanner::MPIScanner) = getDevices(scanner, SurveillanceUnit)
function getSurveillanceUnit(scanner::MPIScanner)
  surveillanceUnits = getSurveillanceUnits(scanner)
  if length(surveillanceUnits) > 1
    error("The scanner has more than one surveillance unit device. Therefore, a single surveillance unit cannot be retrieved unambiguously.")
  else
    return surveillanceUnits[1]
  end
end