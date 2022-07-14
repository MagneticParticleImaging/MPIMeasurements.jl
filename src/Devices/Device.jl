export Device, DeviceParams, deviceID, params, dependencies, dependency, hasDependency, init, _init, checkDependencies

abstract type VirtualDevice <: Device end

"""
Abstract type for all device parameters

Every device must implement a parameter struct allowing for
automatic instantiation from the configuration file.
"""
abstract type DeviceParams end

Base.close(device::Device) = @warn "The device type `$(typeof(device))` has no `close` function defined."

function validateDeviceStruct(device::Type{<:Device})
  requiredFields = [:deviceID, :params, :optional, :present, :dependencies]
  missingFields = [x for x in requiredFields if !in(x, fieldnames(device))]
  if length(missingFields) > 0
    msg = "Device struct $(string(device)) is missing the required fields " * join(missingFields, ", ", " and ")
    throw(ScannerConfigurationError(msg))
  end
end

macro add_device_fields(paramType)
  return esc(quote 
    #"Unique device ID for this device as defined in the configuration."
    deviceID::String
    #"Parameter struct for this devices read from the configuration."
    params::$(paramType)
    #"Flag if the device is optional."
	  optional::Bool = false
    #"Flag if the device is present."
    present::Bool = false
    #"Vector of dependencies for this device."
    dependencies::Dict{String,Union{Device,Missing}}
  end)
end

"Retrieve the ID of a device."
deviceID(device::Device) = device.deviceID 

"Retrieve the parameters of a device."
params(device::Device) = device.params

"Check whether the device is optional."
isOptional(device::Device) = device.optional

"Check whether the device is present."
isPresent(device::Device) = device.present

"Retrieve the dependencies of a device."
dependencies(device::Device) = device.dependencies

"Retrieve all dependencies of a certain type."
dependencies(device::Device, type::DataType) = [dependency for dependency in Base.values(dependencies(device)) if dependency isa type]

"Retrieve a single dependency of a certain type and error if there are more dependencies."
function dependency(device::Device, type::DataType)
  dependencies_ = dependencies(device, type)
  if length(dependencies_) > 1
    throw(ScannerConfigurationError("Retrieving a dependency of type `$type` for the device with the ID `$(deviceID(device))` "*
                                    "returned more than one item and can therefore not be retrieved unambiguously."))
  else
    return dependencies_[1]
  end
end

"Check whether the device has a dependency of the given `type`."
hasDependency(device::Device, type::DataType) = length(dependencies(device, type)) > 0

"Retrieve a single dependency with a certain device ID."
function dependency(device::Device, dependencyID::String)
  dependencies_ = dependencies(device)
  
  for (dependencyIDLoop, dependency_) in dependencies_
    if deviceID(dependency_) == dependencyID
      return dependency_
    end
  end
end

"Retrieve all expected dependencies of a device."
expectedDependencies(device::Device)::Vector{DataType} = vcat(neededDependencies(device), optionalDependencies(device))

"Check if a device is an expected dependency of another device."
function isExpectedDependency(device::Device, dependency::Device)
  for expectedDependency in expectedDependencies(device)
    if typeof(dependency) <: expectedDependency
      return true
    end
  end

  return false
end

@mustimplement _init(device::Device)
@mustimplement neededDependencies(device::Device)::Vector{DataType}
@mustimplement optionalDependencies(device::Device)::Vector{DataType}

function init(device::Device)
  @info "Initializing $(typeof(device)) with ID `$(deviceID(device))`"
  
  # Only init a device if all dependencies are present
  uninitDependencies = []
  for dev in Base.values(dependencies(device)) # Should only be of type <: Device at this point
    if !isPresent(dev)
      push!(uninitDependencies, deviceID(dev))
    end
  end
  if length(uninitDependencies) > 0
    msg = "Initialization order error: The device $(deviceID(device)) cannot be initialized because it depends on the uninitialized devices " * join(uninitDependencies, ", ", " and ")
    throw(ScannerConfigurationError(msg))
  end

  _init(device)
  device.present = true
end

function checkDependencies(device::Device)
  # Check if all needed dependencies are assigned
  for neededDependency in neededDependencies(device)
    if !hasDependency(device, neededDependency)
      throw(ScannerConfigurationError("The device with ID `$(deviceID(device))` "*
                                      "needs a dependency of type $(neededDependency) "*
                                      "but it is not assigned."))
      return false
    end
  end

  # Check if superfluous dependencies are assigned
  for (dependencyID, dependency) in dependencies(device)
    if !isExpectedDependency(device, dependency)
      @warn "The device with ID `$(deviceID(device))` has a superfluous dependency "*
            "to a device with ID `$dependencyID`."
    end
  end
  
  return true
end