# Devices

A scanner is composed of multiple devices. Probably the most important device in most systems is the data acquisition (DAQ), but depending on the scope of the system, the setup can also include robots, temperature sensors and many other.

## Configuration

Each scanner is defined within a separate configuration directory with a structure as described below. 

## File structure

The file structure for a scanner configuration is

```
ScannerName/
├── Protocols/
│   └── <protocol 1 name>.toml
│   └── <protocol 2 name>.toml
│   └── ...
├── Sequences/
│   └── <sequence 1 name>.toml
│   └── <sequence 2 name>.toml
│   └── ...
└── Scanner.toml
```

Head to the the [Protocols](@ref) and [Sequences](@ref) section to learn more about setting up those.

## Scanner.toml

All devices can be configured in the scanner configuration file `Scanner.toml`. The markup is based on [TOML](https://toml.io/en/) and is structured as follows:

### General section

The general section contains the details of the scanner. The fields correspond to the `scanner` group of the [MPI data format (MDF)](https://github.com/MagneticParticleImaging/MDF) and are used when writing a measurement to disk.
All fields that have units will be parsed with [Unitful](https://github.com/PainterQubits/Unitful.jl) and should therefore be denoted as strings with the unit attached without a space. This also applies to the [Devices section](@ref).

```toml
[General]
boreSize = "XXmm"
facility = "<facility>"
manufacturer = "<manufacturer>"
name = "<scanner name>"
topology = "<FFP|FFL|MPS>"
gradient = "XXT/m"
```

### Devices section

All devices that shall be usable by the scanner should be denoted in this section. It describes the hardware properties like maximum and minimum values for DAQ devices, connection details like e.g. IPs, etc.
Since the initialization order sometimes matters, it has to be set explicitly in the main section by putting the device IDs in the correct order. Each device must at least give a `deviceType` which corresponds to the respective device struct.

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
```

## Creating a new device

**TODO**: Add description on new devices.