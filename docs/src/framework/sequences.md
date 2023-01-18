# Sequences
A `Sequence` is an abstract description of magnetic fields being applied during an experiment, as well as the used acquisition parameters. It is the data acquisition (DAQ) `Device` responsibility to produce and acquire the necessary signals described in a `Sequence`.

`MPIMeasurements.jl` contains an implementation of a `DAQ` based on the [RedPitayaDAQServer](https://github.com/tknopp/RedPitayaDAQServer) project. This, together with the [MPI data format (MDF)](https://github.com/MagneticParticleImaging/MDF), motivated the structure of a `Sequence`. However, any `DAQ` capable of producing the following signals could be used instead. A `DAQ` device needs to map the channel and components mentioned in a `Sequence`, into its own representation.

A `Sequence` contains a general description of itself, acquisition parameters and a list of magnetic fields. `Sequences` are constructed from a `Scanners` configuration directory as follows:

```julia-repl
julia> sequence = Sequence(scanner, "<sequence X name>")
```

## General Settings
The general section contains a description string for the sequence, as well as the target scanner name and lastly the base frequency from which the other magnetic field are derived.

```toml
[General]
description = "<Sequence Description>"
targetScanner = "<ScannerName>"
baseFrequency = "125MHz"
```
## Acquisition Settings
The acquisition settings list which receive channels of a `Scanner` should be acquired during a measurement and with which sampling rate. Furthermore, it contains a description of the length of a measurement or rather how much samples should be acquired and if they should be averaged. This section is related to the acquisition parameters in an MDF file. 
```toml
[Acquisition]
channels = ["rx1", "rx2"]
bandwidth = "<XX>Hz"
numPeriodsPerFrame = 1
numFrames = 1
numAverages = 1
```
## Magnetic Fields

The last section of a `Sequence` is the description of the desired magnetic fields. A `Sequence` can contain any number of magnetic fields, while each magnetic field in turn can contain any number of transmit channel (`TxChannel`).

`TxChannel` can be grouped into electrical or mechanical channel. The former can be further divided into periodic and into acyclic electrical channel, while the latter can be divided into mechanical translation and mechanical rotation channel.

Next to these `TxChannel`, a magnetic field also contains parameters if its channel should be controlled, decoupled or should feature ramping of its signals.

```toml
[Fields.df] # Drive Field 
control = true
```
### Periodic Electrical Channel
A periodic electrical channel is a `TxChannel`, that contains any number of electrical periodic functions or components. Each component is described by a divider referencing the base frequency, as well as an amplitude, phase and waveform. These components are modeled after the drive field parameters of the MDF.

```toml
[Fields.df.dfx] # X Channel
type = "PeriodicElectricalChannel"
offset = "0.0mT"

[Fields.df.dfx.c1] # Sine Wave
type = "PeriodicElectricalComponent"
divider = 4864
amplitude = ["0.0025T"]
phase = ["0.0rad"]
waveform = "sine"
```
By default periodic electrical channel are interpreted as drive fields and in particular count towards the length of a drive field cycle.
### Acyclic Electrical Channel
An acyclic electrical channel describes changing non-periodic electrical signals. These can be used to describe multi-patch sequences as they can provide descriptions for changing gradient and offset signals during a frame.

```toml
[Fields.ff] # Focus Field
control = false

[Fields.ff.patches]
type = "ContinuousElectricalChannel"
dividerSteps = 364800
divider = 31008000
amplitude = "3.8A"
offset = "10.0A"
phase = "3.14rad"
waveform = "triangle"
```
The above example shows an acylic electrical channel with a 4-Hz triangular waveform sampled uniformly at 85 points. 

Instead of sampling pre-defined analytical functions, it is also possible to directly state a series of values.