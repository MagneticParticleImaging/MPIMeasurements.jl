# Changelog

## 0.6.0

### Most Important Breaking Changes
- **Breaking**: There have been multiple changes to arguments in the Scanner.toml related to both devices and the scanner, please find a detailed migration guide [https://magneticparticleimaging.github.io/MPIMeasurements.jl/dev/config/upgrade.html#v0.5-to-v0.6](here)
- **Breaking**: the receive transfer function is now defined per receive channel instead of per scanner, this allows the sequence to flexibly select receive channels and assemble the correct TF

### Improved support for arbitrary waveform components
- define an `ArbitraryElectricalComponent` by using an amplitude, phase and base waveform (`values`)
- `values` can either be a vector or the filename to an .h5 file with field "/values" located in the new `Waveforms` folder of the Scanner
- added TX controller for arbitrary waveform components (see next section)

### Updated TxDAQController and Feedback
- completely reworked internals of `TxDAQController` device
- added new `ControlSequence` type structure to implement a tx controller to control arbitrary waveform and DC enabled channels, the type of ControlSequence to be used is automatically detected based on the requirements of the sequence that should be controlled, the old behaviour is implemented as `CrossCouplingControlSequence`
- split `amplitudeAccuracy` and `fieldToVolDeviation` settings into relative and absolute values to improve flexibility, the two conditions are combined as OR
- `phaseAccuracy` has a unit now
- added caching of last control values to increase control speed of repeating measurements
- feedback calibration is now handled as a complex valued, optionally frequency dependent transfer function
- forward calibration of tx channels can now be a complex number to include a phase shift
- removed `correctCrossCoupling` setting from TxDAQControllerParams, if any field sets decouple=true the controller will try to decouple it


### New MPS Measurement Protocol
Updated the `MPSMeasurementProtocol` used to measure hybrid system matrix measurements in an MPS.
New features include:
- offsets are now defined as a `ProtocolOffsetElectricalChannel` directly in the sequence instead of the protocol
- added a wait time per offset channel, to account for slow DC sources. Any data recorded during this settling time will be discarded
- added functionality to RedPitayaDAQ channels to use H-bridges for switching the polarity of DC offsets
- new algorithm ordering the channels to reduce total wait time
- save data in proper system matrix format for hybrid reconstruction

### New MultiSequenceSystemMatrixProtocol
Measures a (hybrid) system matrix that is defined by one `Sequence` per position, this can be used to flexibly vary any component of the field sequence like amplitudes, phases and offsets. The individual measurements will be saved together as frames in a joint MDF file. Between the individual measurements the system can be instructed to wait until the value of a temperature sensor is below a configurable threshhold.

### General Updates
- the phase of signal components can now also be one of {"cosine", "cos", "sine", "sin", "-cosine", "-cos", "-sine", "-sin"} instead of giving the phase directly
- a magnetic field that needs to be decoupled will also require control
- frequency dividers can now be rational, the trajectory length will still be an integer using the lcm of the numerators
- all field amplitudes can now be given as a voltage, circumventing field control
- add `block` keyword argument to `startProtocol` of the ConsoleProtocolHandler to only return from the function when the protocol is finished
- devices now have a config file parameter containing the file from which they were initialized
- re-included implementation for fiber optical temperature sensor (FOTemp.jl)
- small fixes regarding different Isel robot versions
- renamed the `saveAsSystemMatrix` parameter to `saveInCalibFolder`
- removed `defaultSequence` parameter from scanner as the sequence is always defined in the protocol
- small updates to documentation