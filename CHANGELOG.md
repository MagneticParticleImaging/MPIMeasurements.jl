# Changelog

## Unreleased

### Breaking changes
- **Breaking**: removed `isBackground` for `AcquisitionSettings` and `Sequence` (and its export); it accessed a field that does not exist and always failed
- **Breaking**: `rxDecimation` returns an `Int` and throws a `ScannerConfigurationError` if the decimation is not an integer; the Red Pitaya DAQ requires an even decimation from 8 to 8192
- **Breaking**: `dfStrength` and `dfPhase` return the values of all periods and throw a `SequenceConfigurationError` if the drive-field components have different numbers of periods
- **Breaking**: `fillMDFMeasurement`/`saveasMDF` with background data throw an `ArgumentError` if only one of `temperatures` and the new keyword `bgTemperatures` is given; the temperatures are extended by the background frames

### Fixes and minor changes
- `unitIsTesla(::StepwiseElectricalChannel)` no longer calls a deprecated Unitful method
- memory-mapping protocol files no longer leaves a file stream open per mapped array
- `isless` for two non-stepwise `TxChannel`s returns `false`, so sorting channels uses a valid order
- the example sequences in `config/` are updated to the current sequence format and load again
- `MultiSequenceSystemMatrixProtocol`: resuming a measurement with the stored sequences adopts them as the protocol sequences, and the background measurements are repeated `numBGMeas` times as in a new measurement
- measurement protocols turn the amplifiers and the AC power off and re-enable temperature control and robots also when switching on one of these devices fails
- sequences: fixed loading `ContinuousMechanicalTranslationChannel`, `cycleDuration` of continuous electrical and mechanical channels, the rotation direction "standstill", the amplitude of `SweepElectricalComponent`, replacing a component by its id and writing offset and rotation channels to TOML
- sequences: integer values with prefixed units (e.g. `"2mT"`) can be loaded; electrical values are read by `parseFieldUnit`, whose errors name the key and the channel or component; `"a:b"` ranges are collected like `"a:b:c"`; `sequenceFromDict` leaves its input dict intact
- `WAVEFORM_ARBITRARY` is exported
- MDF: existing temperatures are kept when none are given, fixed `deltaSampleSize` in `fillMDFCalibration`, default study time in `saveasMDF`, and conversion between `Tracer` and `MDFv2Tracer`
- clearer errors for unknown channel, component and device types and for invalid component units
- extended test suite and CI (separate job for subpackages)

## 0.6.0

### Most Important Breaking Changes
- **Breaking**: There have been multiple changes to arguments in the Scanner.toml related to both devices and the scanner, please find a detailed migration guide [here](https://magneticparticleimaging.github.io/MPIMeasurements.jl/dev/config/upgrade.html#v0.5-to-v0.6)
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
