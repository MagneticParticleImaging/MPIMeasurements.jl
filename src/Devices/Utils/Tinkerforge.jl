
# Default for all devices
isTinkerforgeDevice(::Device) = false

export TinkerforgeDevice
struct TinkerforgeDevice <: Device end

export host
host(device::T) where T <: Device = isTinkerforgeDevice(device) ? host(TinkerforgeDevice(), device) : error("`host` not implemented for device of type $(typeof(device)).")
host(::TinkerforgeDevice, device::T) where T <:Device = device.params.host

export port
port(device::T) where T <: Device = isTinkerforgeDevice(device) ? port(TinkerforgeDevice(), device) : error("`port` not implemented for device of type $(typeof(device)).")
port(::TinkerforgeDevice, device::T) where T <:Device = device.params.port

export uid
uid(device::T) where T <: Device = isTinkerforgeDevice(device) ? uid(TinkerforgeDevice(), device) : error("`uid` not implemented for device of type $(typeof(device)).")
uid(::TinkerforgeDevice, device::T) where T <:Device = device.params.uid