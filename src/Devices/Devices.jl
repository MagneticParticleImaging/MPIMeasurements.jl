#include("SerialDevices/SerialDevices.jl")
include("Utils/UtilDevices.jl")
include("DAQ/DAQ.jl")
include("Display/Display.jl")
include("ElectricalSource/ElectricalSource.jl")
include("GaussMeter/GaussMeter.jl")
include("Motor/Motor.jl")
include("Robots/Robots.jl")
include("SurveillanceUnit/SurveillanceUnit.jl")
include("Sensors/Sensors.jl")
include("Virtual/Virtual.jl")


# List our own enums to avoid accidentally converting a different enum
# Did not list enums like LakeShoreF71GaussMeterConnectionModes atm, because their convert function uses specific strings
# and not the enum name
for enum in [TriggerMode, RampingMode]
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