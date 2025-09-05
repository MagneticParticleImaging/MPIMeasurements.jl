# Scanner

A `Scanner` represents a composition of hard- and software components or `Devices` and a set of configuration files. Each scanner is defined in its own configuration directory with the following structure:

```
ScannerName/
├── Sequences/
│   └── <sequence 1 name>.toml
│   └── <sequence 2 name>.toml
│   └── ...
├── Devices/
│   └── <device 1 name>.toml
│   └── <device 2 name>.toml
│   └── ...
├── Protocols/
│   └── <protocol 1 name>.toml
│   └── <protocol 2 name>.toml
│   └── ...
└── Scanner.toml
```

The `Scanner` data structure is the entry point for working with an MPI system within `MPIMeasurements.jl`, as it manages both the composition of `Devices` and the construction of `Sequences` and `Protocols` based on the configuration directory. A `Scanner` is constructed with the `MPIScanner` function and the name of the desired configuration directoy:  

```julia-repl
julia> scanner = MPIScanner("ScannerName");
```

During construction, all `Devices` of the scanner are also constructed and initialised according to the parameters contained in the `Scanner.toml` configuration file.

## Scanner.toml

The `Scanner.toml` contains the configuration parameters of the `Scanner` and is structured into three sections. 

### General Section

The general section contains the details of the scanner. The fields correspond to the `scanner` group of the [MPI data format (MDF)](https://github.com/MagneticParticleImaging/MDF) and are used when writing a measurement to disk.
All fields that have units will be parsed with [Unitful](https://github.com/PainterQubits/Unitful.jl) and should therefore be denoted as strings with the unit attached without a space. This also applies to the [Device Section](@ref).

```toml
[General]
boreSize = "XXmm"
facility = "<facility>"
manufacturer = "<manufacturer>"
name = "<scanner name>"
topology = "<FFP|FFL|MPS>"
gradient = "XXT/m"
```

In addition, the General section contains hints for `Protocol`, scripts and GUI implementations, such as on which Julia threads to run certain threads or which default `Sequences` to display.

```toml
defaultProtocol = "<protocol X name>"
datasetStore = "<file path">
# Which Julia threads to run common tasks on
producerThreadID = 1
protocolThreadID = 2

consumerThreadID = 3
serialThreadID = 4
```

### Device Section

All devices that can be used by the scanner should be listed in this section. It describes the hardware properties such as maximum and minimum values for DAQ devices, connection details such as IPs, etc. Aside from common parameters such as the `deviceType` or the `dependencies`, the parameters of each device type can differ.

Since the initialization order sometimes matters, it must be explicitly specified in the main section by putting the device IDs in the correct order. Each device must specify at least one `deviceType` corresponding to the respective device structure.

```toml
[Devices]
initializationOrder = [
    "my_device_id1",
    "my_device_id2"
]

[Devices.my_device_id1]
deviceType = "<device type as given by the struct name>"
parameter1 = 1000
parameter2 = "25kHz"

[Devices.my_device_id2]
deviceType = "<device type as given by the struct name>"
dependencies = ["my_device_id1"]
parameter = "192.168.1.100"
```