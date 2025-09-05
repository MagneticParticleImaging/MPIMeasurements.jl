# Devices

A `Device` is a configurable and stateful (interface to) a hard- or software component, such as the interface to a robot or a software component that controls the phase and amplitude of a drive field.

The `Device` types form a type hierarchy with the root type 
```julia
abstract type Device end
```
and feature generic interfaces and implementations. However, due to the nature of Julias multiple-dispatch, each `Device` can specialize and fully express its features at the cost of potentially diverging from its generic interface.

During `Scanner` construction, all its `Device`s listed in the initialization order parameter are also initialized. During the `Device` initialization, the `Device` can access its own parameters as given in the configuration file and all the `Device`s it depends on.

## Structure

Each concrete `Device` implementation is a mutable composite type in the `Device` type hierarchy. 



The fields of each `Device` can be grouped into three parts. 
### Common Device Fields
Every `Device` must have the fields `deviceID, params, present` and `dependencies`, as these are the fields used during automatic instantiation of a `Scanner`.

The `deviceID` is the name of a specific `Device` instance and corresponds to the name/key used in the `Scanner.toml`. The `params` field contains the user provided configuration parameters (see [Device Parameter Field](@ref)). 

Lastly the `present` field denotes if a `Device` was succesfully initialized and the `dependencies` field contains a `Dict` containing all the dependent `Devices` of the current `Device`. 

### Device Parameter Field
Every `Device` must implement a type for the configuration parameters used during automatic instantiation. 

These parameter types must inherit from the `DeviceParams` type and must be named like the `Device` type they belong to with the added suffix of `Params`:

```julia
mutable struct Example <: Device
    ...
end
struct ExampleParams <: DeviceParams
    parameter1::String
    parameter2::Int64
end
```
It is also possible to offer several variants of configuration parameters by providing a type hierarchy with an abstract root type `<DeviceType>Params`.

### Internal Device Fields
And finally a `Device` can contain any number of "internal" fields, these are intended to be used to handle resources, such as connections, or any number of internal states. These fields need to be provided with a default value.

### Initialization
Automatic initialization of a `Device` happens in two phases. First, the key/value pairs of the `Scanner.toml` for a given `Device` are passed to all potential `DeviceParams` as a constructor. If a fitting paramter type was found, the corresponding `Device` type is constructed with the parameter type set.

Afterwards, the `_init` function of the constructed `Device` is called, which executes user-defined code that should check the provied paramteres and prepare internal device fields. During this second process, a `Device` can access all the `Device`s it depends on.

## Functions
Todo

## Implementing New Devices
The following example shows how to implement a new `Device`. The chosen device is an interface to a temperature sensor, that can be queried via TCP/IP to return new temperature values. The made up sensor only has one channel/value.

To "simplify" configuration and showcase the `DeviceParams`, a user can either directly specify an IP or provided a number of IPs which the `Device` sequentially checks in the `Scanner.toml`.

Checking the existing `Device` tree shows that there are already a number of temperature sensor implementation and in particular, there is an abstract `TemperatureSensor` type. Therefore, the new `Device` should inherit from this type. Furthermore, the abstract type also defines a number of functions, which need to be implemented for the new sensor.

This gives the following starting point, which will evolve throughout the example:

```julia
mutable struct IPTempSensor <: TemperatureSensor
    ...
end
abstract type IPTempSensorParams <: DeviceParams end
struct IPTempSensorDirectParams <: IPTempSensorParams
    ip::String
    channelName::String
end
struct IPTempSensorSequentialParams <: IPTempSensorParams
    ips::Vector{String} # Note ip != ips, the names need to differ
    channelName::String
end
```
The start already shows the type hierarchy for two types of parameters. It is only important that the abstract type follows the rule of device name and params suffix.

Next one needs to implement the Params constructor, which takes a `Dict` as input. Here, `MPIMeasurements.jl` and Julia offers a few convience options.
First, one can use the `Base.@kwdef` macro. This macro automatically defines keyword based constructors for a structure and it allows the definition of default values:
```julia
Base.@kwdef struct IPTempSensorDirectParams <: IPTempSensorParams
    ip::String
    channelName::String = "N/A"
end
```
This allows the structure to be constructed like this:
```julia
julia> params = IPTempSensorDirectParams(ip="192.168.1.100")
```
However, this is still not enough to simply construct a parameter object from the `Dict`, as the `Dict` contains a mapping of String to values. For the constructor, one needs a mapping of Symbols to values. Symbols in Julia are [interned Strings](https://en.wikipedia.org/wiki/String_interning). This conversion is something provided by `MPIMeasurements.jl` with the `params_from_dict` function:
```julia
Base.@kwdef struct IPTempSensorDirectParams <: IPTempSensorParams
    ip::String
    channelName::String = "N/A"
end
IPTempSensorDirectParams(dict::Dict) = params_from_dict(IPTempSensorDirectParams, dict)
```
The other parameter type requires the same changes. Now with the macro and provided function, the constructor for the parameter types is finished. In the `Scanner.toml` a user can now write something like:
```toml
[Devices.ipSensor]
deviceType = "IPTempSensor"
ip = "192.168.1.100"
channelName = "Drive Field Temp"
```
and `MPIMeasurements.jl` would find the `IPTempSensorDirectParams` in the first phase of `Device` construction.

Now the parameter type must be added to the `Device` type itself, together with all other mandatory fields. Here, `MPIMeasurements.jl` provides another macro, which given a parameter type name, adds all the mandatory fields to a struct:
```julia
Base.@kwdef mutable struct IPTempSensor <: TemperatureSensor
    @add_device_fields IPTempSensorParams
    conn::Union{Nothing, TCPSocket} = nothing
end
```
The structure was also provided with a keyword constructor and an added internal field to hold the necessary TCP connection. As this is an internal field, it needed to be provided with a default value. 

The final step for automatic initialization is implementing the mandatory `Device` functions. The sensor itself does not have any required dependencies, which means those can be left empty:
```julia
neededDependencies(::IPTempSensor) = []
optionalDependencies(::IPTempSensor) = []
```
This only leaves the `_init` function, during which the parameters need to be checked and the TCP connection established. However, the `Device` has two different types of parameters. This can be handled with Julias multiple-dispatch:
```julia
function _init(sensor::IPTempSensor) 
    sensor.conn = establishConnection(sensor, sensor.params)
    if isnothing(sensor.conn)
        throw(ScannerConfigurationError("Could not connect to sensor"))
    end
end

function establishConnection(sensor::IPTempSensor, params::IPTempSensorDirectParams)
    conn = connect(params.ip)
    if # Test if connected to correct device 
        return conn
    else
        return nothing
    end
end

function establishConnection(sensor::IPTempSensor, params::IPTempSensorSequentialParams)
    for ip in params.ips
        conn = connect(params.ip)
        # Return if valid connection
    end
    return nothing
end
```
Now the sensor can be automatically initialized by `MPIMeasurements.jl`. In order to be used as a temperature sensor, however, the sensor-specific functions are still missing. As a last example, here are three of missing implemented functions:
```julia
numChannels(sensor::IPTempSensor) = 1
getChannelNames(sensor::IPTempSensor) = [sensor.params.channelName]
function getTemperature(sensor::IPTempSensor, channel::Int)
    if channel != 1
        throw(ArgumentError("IPTempSensor only has one channel, can not access channel $channel"))
    end
    write(sensor.conn, "TEMP?")
    reply = readline(sensor.conn)
    return parse(reply, Float64)
end
```
Once these are implemented, every `Protocol`, script and GUI that works with the other temperature sensors will seamlessly work with the new one. But it is also possible to specialise specific parts of `Protocol` to have unique behaviour for this particular sensor using multiple-dispatch.