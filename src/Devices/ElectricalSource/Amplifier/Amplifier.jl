export Amplifier, AmplifierMode, AMP_VOLTAGE_MODE, AMP_CURRENT_MODE, AmplifierPowerSupplyMode,
       AMP_HIGH_POWER_SUPPLY,AMP_MID_POWER_SUPPLY, AMP_LOW_POWER_SUPPLY, getAmplifiers, getAmplifier, state,
       turnOn, turnOff, mode, powerSupplyMode, matchingNetwork, temperature, toCurrentMode,
       toVoltageMode, toLowPowerSupplyMode, toHighPowerSupplyMode

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

@enum AmplifierPowerSupplyMode begin
  AMP_LOW_POWER_SUPPLY=0
  AMP_MID_POWER_SUPPLY=1
  AMP_HIGH_POWER_SUPPLY=3
end

function convert(::Type{AmplifierPowerSupplyMode}, x::String)
  if contains(lowercase(x),"low")
    return AMP_LOW_POWER_SUPPLY
  elseif contains(lowercase(x),"mid")
    return AMP_MID_POWER_SUPPLY
  elseif contains(lowercase(x),"high")
    return AMP_HIGH_POWER_SUPPLY
  else
    throw(ScannerConfigurationError("The given amplifier mode `$x` for is not valid. Please use `low voltage` or `high voltage`."))
  end
end

abstract type Amplifier <: ElectricalSource end

Base.close(amp::Amplifier) = nothing

Base.@deprecate_binding AmplifierVoltageMode AmplifierPowerSupplyMode
@deprecate voltageMode(amp::Amplifier) powerSupplyMode(amp)
@deprecate voltageMode(amp::Amplifier, mode::AmplifierPowerSupplyMode) powerSupplyMode(amp, mode)

@mustimplement state(amp::Amplifier)
@mustimplement turnOn(amp::Amplifier)
@mustimplement turnOff(amp::Amplifier)
@mustimplement mode(amp::Amplifier)::AmplifierMode
@mustimplement mode(amp::Amplifier, mode::AmplifierMode)
@mustimplement powerSupplyMode(amp::Amplifier)::AmplifierPowerSupplyMode
@mustimplement powerSupplyMode(amp::Amplifier, mode::AmplifierPowerSupplyMode)
@mustimplement matchingNetwork(amp::Amplifier)::Integer
@mustimplement matchingNetwork(amp::Amplifier, network::Integer)
@mustimplement temperature(amp::Amplifier)::typeof(1.0u"°C")
@mustimplement channelId(amp::Amplifier)

function turnOn(amps::Vector{<:Amplifier})
  if !isempty(amps)
    @sync for amp in amps
      @async turnOn(amp)
    end
  end
end

export getAmplifiers
getAmplifiers(scanner::MPIScanner) = getDevices(scanner, Amplifier)

export getAmplifier
getAmplifier(scanner::MPIScanner) = getDevice(scanner, Amplifier)

function getRequiredAmplifiers(scanner::MPIScanner, sequence::Sequence)
  return getRequiredAmplifiers(getAmplifiers(scanner), sequence)
end
function getRequiredAmplifiers(device::Device, sequence::Sequence)
  if hasDependency(device, Amplifier)
    return getRequiredAmplifiers(dependencies(device, Amplifier), sequence)
  end
  return []
end
function getRequiredAmplifiers(amps::Vector{<:Amplifier}, sequence::Sequence)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(union(acyclicElectricalTxChannels(sequence), periodicElectricalTxChannels(sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
  return amps
end

"""
Sets the amplifier to current mode.
"""
toCurrentMode(amp::Amplifier) = mode(amp, AMP_CURRENT_MODE)

"""
Sets the amplifier to voltage mode.
"""
toVoltageMode(amp::Amplifier) = mode(amp, AMP_VOLTAGE_MODE)

@deprecate toLowVoltageMode(amp::Amplifier) toLowPowerSupplyMode(amp)
"""
Sets the amplifier to low voltage mode.
"""
toLowPowerSupplyMode(amp::Amplifier) = powerSupplyMode(amp, AMP_LOW_POWER_SUPPLY)

@deprecate toHighVoltageMode(amp::Amplifier) toHighPowerSupplyMode(amp)
"""
Sets the amplifier to high voltage mode.
"""
toHighPowerSupplyMode(amp::Amplifier) = powerSupplyMode(amp, AMP_HIGH_POWER_SUPPLY)


include("SimulatedAmplifier.jl")
include("HubertAmplifier.jl")
