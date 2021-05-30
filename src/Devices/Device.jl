export Device, DeviceParams, deviceID, params, dependencies, dependency, hasDependency, init, checkDependencies

"""
Abstract type for all device parameters

Every device must implement a parameter struct allowing for
automatic instantiation from the configuration file.
"""
abstract type DeviceParams end

"""
Abstract type for all devices

Every device has to implement its own device struct which identifies it.
A concrete implementation should contain e.g. the handle to device ressources
or internal variables.
The device struct must at least have the fields `deviceID`, `params` and `dependencies` and
all other fields should have default values.
"""
abstract type Device end

"Retrieve the ID of a device."
deviceID(device::Device) = :deviceID in fieldnames(typeof(device)) ? device.deviceID : error("The device struct for `$(typeof(device))` must have a field `deviceID`.")

"Retrieve the parameters of a device."
params(device::Device) = :params in fieldnames(typeof(device)) ? device.params : error("The device struct for `$(typeof(device))` must have a field `params`.")

"Retrieve the dependencies of a device."
dependencies(device::Device) = :dependencies in fieldnames(typeof(device)) ? device.dependencies : error("The device struct for `$(typeof(device))` must have a field `dependencies`.")

"Retrieve all dependencies of a certain type."
dependencies(device::Device, type::DataType) = [dependency for dependency in values(dependencies(device)) if dependency isa type]

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

"Chech whether the device has a dependency of the given `type`."
hasDependency(device::Device, type::DataType) = length(dependencies(device, type)) > 0

@mustimplement init(device::Device)
@mustimplement checkDependencies(device::Device)