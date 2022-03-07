using Graphics: @mustimplement

export Amplifier, AmplifierMode, AMP_VOLTAGE_MODE, AMP_CURRENT_MODE, AmplifierVoltageMode,
       AMP_HIGH_VOLTAGE_MODE, AMP_LOW_VOLTAGE_MODE, getAmplifiers, getAmplifier, state,
       turnOn, turnOff, mode, voltageMode, matchingNetwork, temperature, toCurrentMode,
       toVoltageMode, toLowVoltageMode, toHighVoltageMode

@enum AmplifierMode begin
  AMP_VOLTAGE_MODE
  AMP_CURRENT_MODE
end

function convert(::Type{AmplifierMode}, x::String)
  if lowercase(x) == "voltage"
    return AMP_VOLTAGE_MODE
  elseif  lowercase(x) == "current"
    return AMP_CURRENT_MODE
  else
    throw(ScannerConfigurationError("The given amplifier mode `$x` for is not valid. Please use `voltage` or `current`."))
  end
end

@enum AmplifierVoltageMode begin
  AMP_HIGH_VOLTAGE_MODE
  AMP_LOW_VOLTAGE_MODE
end

function convert(::Type{AmplifierVoltageMode}, x::String)
  if lowercase(x) == "low voltage"
    return AMP_LOW_VOLTAGE_MODE
  elseif  lowercase(x) == "high voltage"
    return AMP_HIGH_VOLTAGE_MODE
  else
    throw(ScannerConfigurationError("The given amplifier mode `$x` for is not valid. Please use `low voltage` or `high voltage`."))
  end
end

abstract type Amplifier <: Device end

Base.close(amp::Amplifier) = nothing

@mustimplement state(amp::Amplifier)
@mustimplement turnOn(amp::Amplifier)
@mustimplement turnOff(amp::Amplifier)
@mustimplement mode(amp::Amplifier)::AmplifierMode
@mustimplement mode(amp::Amplifier, mode::AmplifierMode)
@mustimplement voltageMode(amp::Amplifier)::AmplifierVoltageMode
@mustimplement voltageMode(amp::Amplifier, mode::AmplifierVoltageMode)
@mustimplement matchingNetwork(amp::Amplifier)::Integer
@mustimplement matchingNetwork(amp::Amplifier, network::Integer)
@mustimplement temperature(amp::Amplifier)::typeof(1.0u"°C")
@mustimplement channelId(amp::Amplifier)

getAmplifiers(scanner::MPIScanner) = getDevices(scanner, Amplifier)
function getAmplifier(scanner::MPIScanner)
  amplifiers = getGaussMeters(scanner)
  if length(amplifiers) > 1
    error("The scanner has more than one amplifier device. Therefore, a single amplifier cannot be retrieved unambiguously.")
  else
    return amplifiers[1]
  end
end

"""
Sets the amplifier to current mode.
"""
toCurrentMode(amp::Amplifier) = mode(amp, AMP_CURRENT_MODE)

"""
Sets the amplifier to voltage mode.
"""
toVoltageMode(amp::Amplifier) = mode(amp, AMP_VOLTAGE_MODE)

"""
Sets the amplifier to low voltage mode.
"""
toLowVoltageMode(amp::Amplifier) = voltageMode(amp, AMP_LOW_VOLTAGE_MODE)

"""
Sets the amplifier to high voltage mode.
"""
toHighVoltageMode(amp::Amplifier) = voltageMode(amp, AMP_HIGH_VOLTAGE_MODE)


include("SimulatedAmplifier.jl")
include("HubertAmplifier.jl")