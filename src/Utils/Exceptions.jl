
"""
    Abstract error type for errors in configuration files
"""
abstract type ConfigurationError <: Exception end

"""
    Specialized error type for errors in scanner configuration files
"""
struct ScannerConfigurationError <: ConfigurationError
  message::String
end

"""
    Specialized error type for errors in protocol configuration files
"""
struct ProtocolConfigurationError <: ConfigurationError
  message::String
end

"""
    Specialized error type for errors in sequence configuration files
"""
struct SequenceConfigurationError <: ConfigurationError
  message::String
end

"""
    Base.show(io::IO, ex::ConfigurationError)
Custom printing of `ConfigurationError` subtypes
"""
Base.show(io::IO, ex::ConfigurationError) = print(io, "$(typeof(ex)): $(ex.message)")

"""
    Abstract exception type for exceptions in devices
"""
abstract type AbstractDeviceException <: Exception end

"""
    General exception type for exceptions in devices
"""
struct DeviceException <: AbstractDeviceException
  message::String
  device::Union{Device, Nothing}
end

"""
    Base.show(io::IO, ex::DeviceException)
Custom printing of `DeviceException`
"""
function Base.show(io::IO, ex::DeviceException)
  if isnothing(ex.device)
    print(io, "$(typeof(ex)): $(ex.message)")
  else
    print(io, "$(typeof(ex)) in device with ID `$(ex.device.deviceID)`: $(ex.message)")
  end
end