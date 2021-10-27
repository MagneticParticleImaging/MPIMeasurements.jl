#include("SerialDevices/SerialDevices.jl")
include("Amplifier/Amplifier.jl")
include("DAQ/DAQ.jl")
include("GaussMeter/GaussMeter.jl")
include("Robots/Robots.jl")
include("SurveillanceUnit/SurveillanceUnit.jl")
include("TemperatureSensor/TemperatureSensor.jl")
include("Virtual/Virtual.jl")


# List our own enums to avoid accidentally converting a different enum
# Did not list enums like LakeShoreF71GaussMeterConnectionModes atm, because their convert function uses specific strings
# and not the enum name
for enum in [:RPTriggerMode]
  @eval begin
    T = $enum
    function Base.convert(::Type{T}, x::String)
      try 
        return stringToEnum(x, T)
      catch ex
        throw(ScannerConfigurationError(ex.msg))
      end
    end
  end
end