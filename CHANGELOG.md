# Changelog

## Unreleased

### `dfPeriodsPerOffset` moved from the protocols to the sequence
- `ProtocolOffsetElectricalChannel` has a new field `dfPeriodsPerOffset` that sets the number of
  drive-field periods measured per offset. It is read from the sequence TOML with the optional
  key `dfPeriodsPerOffset` and is serialized back automatically. It defaults to `nothing`, which
  means the channel inherits the value defined by the other offset channels of the sequence, so
  only one channel needs to define it.
- the new accessor `dfPeriodsPerOffset(sequence)` returns the value defined by the sequence's
  offset channels, falling back to 50 if none of them defines one. It throws a
  `SequenceConfigurationError` if several offset channels define different values, since a
  sequence can only measure one number of periods per offset, and if the sequence has no
  `ProtocolOffsetElectricalChannel` at all, since the value is meaningless without one.
- the parameter `dfPeriodsPerOffset` has been removed from `MPSMeasurementProtocolParams`; the
  protocol now takes the value from its sequence during `_init` and stores it in the new field
  `MPSMeasurementProtocol.dfPeriodsPerOffset`.
- `averagePeriodsPerOffset` stays a protocol parameter, since it selects whether the periods of
  an offset are averaged or stored individually.

### Accessors are now extensions of the MPIFiles functions
- `calibration`, `experiment`, `fields`, `measurement`, `study`, `tracer`, `temperature`,
  `description`, `rxNumFrequencies`, `scannerBoreSize`, `scannerFacility`, `scannerManufacturer`,
  `scannerName` and `scannerTopology` are now imported from MPIFiles and extended for
  MPIMeasurements' own types instead of being separate functions that shadowed them. This removes
  the "both X and Y export ..." warnings in downstream packages and makes
  `MPIMeasurements.scannerName === MPIFiles.scannerName` hold.

### Improvements for MultiSequenceSystemMatrixProtocol
- fix reloading of protocol with more than one BG measurement
- improve performance by not writing sequences to file every iteration
- change protocol to be able to turn on/off amplifiers for necessary coil channels

### Improvements for TxDAQController
- fixed some edge cases, preventing crashes or inaccurate guesses in the AW controller
- improved control caching, which should result is less misses due to numerical issues
- speed improvements for AWController by caching calculations and reducing amount of processed frequencies
- fix phase wrap issue dicarding valid control results

### Improvements to RedPitayaDAQ
- added ramp time optimization feature which can be enabled in the Scanner.toml, this can optimize (i.e. reduce) the step size of a RedPitaya sequence to waste less time during the ramping phase, since before a minimum of one step was at least used for ramping, even though it might be shorter

### Improvements for HubertAmplifier
- added differentiation for A1110E and A1110QE amplifiers, model will be automatically detected
- renamed AmplifierVoltageMode to AmplifierPowerSupplyMode to avoid confusion with voltage and current modes, deprecating the related function names
- renamed `voltageMode` to `powerSupplyMode` in HubertAmplifierParams, .toml parsing still works with the old parameter, but outputs a deprecation warning
- implemented getters for powerSupplyMode and mode
- added monitoring of powerloss for A1110E
- do not override startup parameters on every init
- improved parsing of amplifier status
- implemented setting and getting of amplifier ID
- `hubertStatus` returns the decoded status of the amplifier (ready, overload, overtemperature, interlock, power supply level of the A1110E, output on)
- errors instead of silently continuing when the amplifier does not acknowledge a command, does not report its model, reports an invalid power supply level or when an ID longer than 128 bytes is set
- the model detected during `init` is used instead of querying it for every command

### Updated REPL Modes
- to remove the overlap with Julias built-in ALT+M (and the corresponding warning on every load) the Device REPL mode shortcut has been changed to ALT+2
- the MPI REPL mode, which controls the complete scanner has been moved to ALT+1

### Other
- improved error messages during device creation
- `offsetsPerPatch(::MPSMeasurementProtocol)` returns the offset of each stored patch, for protocols that run an `MPSMeasurementProtocol` as part of their measurement

### Technically breaking changes
See also the [upgrade guide](https://magneticparticleimaging.github.io/MPIMeasurements.jl/dev/config/upgrade.html).

Amplifiers:
- the constants `AMP_HIGH_VOLTAGE_MODE` and `AMP_LOW_VOLTAGE_MODE` are removed; use `AMP_HIGH_POWER_SUPPLY` and `AMP_LOW_POWER_SUPPLY` (new: `AMP_MID_POWER_SUPPLY`). `AmplifierVoltageMode` is a deprecated alias of the new enum `AmplifierPowerSupplyMode`, whose instances have different integer values
- `voltageMode` is renamed to `powerSupplyMode`; `voltageMode(amp)`, `voltageMode(amp, mode)`, `toLowVoltageMode` and `toHighVoltageMode` still work but are deprecated
- custom amplifier types must implement `powerSupplyMode(amp)` and `powerSupplyMode(amp, mode)` instead of `voltageMode`
- the `SimulatedAmplifier` parameter `voltageMode` in the Scanner.toml is renamed to `powerSupplyMode`; the old name causes an error when the scanner is loaded (the `HubertAmplifier` still accepts it with a deprecation warning)
- the power supply mode in the Scanner.toml is accepted if it contains `low`, `mid` or `high` (e.g. `"low voltage"` still works)
- `state(::HubertAmplifier)` returns `true` if the output is enabled, like the other amplifiers (in 0.6 it returned the raw status bytes); use `hubertStatus` for the full status
- `temperature(::HubertAmplifier)` returns a `Float64` in °C, as declared by the `Amplifier` interface (in 0.6 it returned an `Int` without unit)

TxDAQController and DAQ:
- `TxDAQController` with arbitrary waveform control: the control is accurate when, for every channel, the mean absolute deviation between desired and measured field over one period is below `absoluteAmplitudeAccuracy` (in 0.6 the maximum deviation over all samples and channels was compared)
- `TxDAQController` with arbitrary waveform control and `controlDC = true`: the control additionally requires the mean field of every channel over one period to deviate by less than the new parameter `dcAccuracy` (default 50 µT) from the desired mean field
- `calibration(txCont::TxDAQController, channelID, frequency)` rounds `frequency` to 1 mHz before looking up the cached control results and before falling back to the calibration of the DAQ
- `applyForwardCalibration!` for arbitrary waveform components: the phase of the base-frequency calibration is removed from the n-th harmonic as n·φ (in 0.6 it was 2π·n·φ)
- `scaledValues(::ArbitraryElectricalComponent)`: a positive `phase` shifts the waveform to earlier times, as for `sin(ωt + φ)`; in 0.6 it was shifted in the opposite direction
- `setTxParams(::RedPitayaDAQ, offsets, amplitudes, phases, awg=nothing)` takes the channel offsets as first argument after the DAQ; the offsets are set together with amplitudes and phases in `prepareTx` instead of in `setupTx`
- `setTxParamsAmplitudes`, `setTxParamsPhases` and `setTxParamsFrequencies` of the `RedPitayaDAQ` take a `ScpiBatch` as second argument and only add commands to it; they no longer send on their own and do not check voltage limits

Other:
- removed `isBackground` for `AcquisitionSettings` and `Sequence`; it never worked
- `dfStrength` and `dfPhase` now return the values of all periods and throw a `SequenceConfigurationError` if the drive-field components have different numbers of periods, before multiple periods were ignored
- `fillMDFMeasurement`/`saveasMDF` with background data and `temperatures` now require the new keyword `bgTemperatures`; previously this caused an error

### New features
- frequencies in a `calibration`/`transferFunction` table in the Scanner.toml can be given with a unit (e.g. `"25 kHz"`); numbers without unit are in Hz, angular frequencies such as `"1 rad/s"` or `"60 rpm"` are not possible
- added verification of valid decimations to `RedPitayaDAQ`

### Fixes
- `RedPitayaDAQ` checks before sending any Tx value that |offset| + sum of |amplitudes| + max |AWG| of every channel is finite and below the channel's `limitPeak`; negative offsets and arbitrary waveforms were not checked before, and offset and amplitudes were only checked separately
- `TxDAQController` works with DataStructures 0.19 (creating the device and resetting the cached control results failed)
- `TxDAQController`: control works without amplifiers, and if turning on an amplifier fails, the amplifiers and the AC power are switched off and temperature control is re-enabled
- `TxDAQController` DC search (`controlDC`): the search restarts from the forward calibration when the last two steps are too close together also for zero or negative DC targets, and stops with an error instead of setting non-finite voltages
- `TxDAQController`: the slew rate of AW sequences with more than 100000 frequencies is no longer overestimated, which could reject valid control values
- clearer error message for an invalid amplifier power supply mode in the configuration
- `ProtocolException` (and thus `CancelException` and `IllegalStateException`) are now a subtype of `Exception`
- `WAVEFORM_ARBITRARY` is now exported for consistency
- if switching on a device fails at the start of a measurement, the amplifiers and the AC power are switched off again and temperature control and robots are re-enabled
- multiple fixes for `MultiSequenceSystemMatrixProtocol`: resuming a measurement compares the sequences, the background sequence and the number of background measurements with the stored ones and can continue with the stored values
- sequences: fixed loading `ContinuousMechanicalTranslationChannel`s and integer values with units (e.g. `"2mT"`), the rotation direction "standstill", `cycleDuration` of continuous channels, the amplitude of `SweepElectricalComponent`, replacing a component by its id, writing offset and rotation channels to TOML, `"a:b"` ranges and sorting channel lists; `sequenceFromDict` no longer modifies its input
- MDF: fixed `deltaSampleSize` in `fillMDFCalibration`, `saveasMDF` without a study time, and the conversion between `Tracer` and `MDFv2Tracer`
- clearer errors for unknown channel, component and device types and for invalid units
- the example sequences and protocols in `config/` load again; removed outdated scripts from `example/`
- fixed a deprecation warning and orphaned file handles

## 0.6.2
- the `calibration` (transfer function) of a DAQ channel in the Scanner.toml can be given as a table that maps frequencies to values (#115)
- compat for MPIFiles 0.19
- CI and Dependabot updates

## 0.6.1
- compat for MPIFiles 0.18

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
