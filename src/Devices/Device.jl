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
The device struct must at least have the fields `deviceID` and `params` and
all other fields should have default values.
"""
abstract type Device end

deviceID(device::Device) = :deviceID in fieldnames(typeof(device)) ? device.deviceID : error("The device struct for `$(typeof(device))` must have a field `deviceID`.")
params(device::Device) = :params in fieldnames(typeof(device)) ? device.params : error("The device struct for `$(typeof(device))` must have a field `params`.")
dependencies(device::Device) = :dependencies in fieldnames(typeof(device)) ? device.dependencies : error("The device struct for `$(typeof(device))` must have a field `dependencies`.")
function dependencies(device::Device, type::DataType)
  return [dependency for dependency in values(dependencies(device)) if dependency isa type]
end

@mustimplement init(device::Device)
@mustimplement checkDependencies(device::Device)