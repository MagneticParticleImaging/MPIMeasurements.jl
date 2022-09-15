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
include("Control/Temperature/TemperatureController.jl")
include("Virtual/Virtual.jl")


# List our own enums to avoid accidentally converting a different enum
# Did not list enums like LakeShoreF71GaussMeterConnectionModes atm, because their convert function uses specific strings
# and not the enum name
for enum in [RedPitayaDAQServer.TriggerMode, RampingMode, TemperatureControlMode]
  @eval begin
    function Base.convert(::Type{$enum}, x::String)
      try
        return stringToEnum(x, $enum)
      catch ex
        throw(ScannerConfigurationError(ex.msg))
      end
    end
  end
end
