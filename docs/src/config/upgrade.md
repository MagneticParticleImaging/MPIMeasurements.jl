# Upgrade Guide
This page should give you hints on what to change in your configuration files when upgrading between breaking releases of this package. This guide focusses on removed or changed parameters not on new features that have a sensible default value, for that please check the release notes.

## v0.5 to v0.6
### Scanner and Devices
- the `transferFunction` parameter is no longer in the [General] section, but is now a per-channel parameter attached to each `DAQRxChannelParams`. Use `transferFunction = "tfFile.h5:2"` to select channel 2 out of the file containing multilpe channels
- the `feedback` group is removed from the tx channels and replaced by two other parameters: `feedback.channelID` is replaced by `feedbackChannelID` in the tx channel directly and `feedback.calibration` is replaced by the `transferFunction` parameter in the corresponding receive channel. The `transferFunction` parameter can correctly parse a single (complex) value with units

### TxDAQController

**Old parameter:**  \
`amplitudeAccuracy`  \
**Replaced by:**  \
`absoluteAmplitudeAccuracy`, absolute control accuracy threshhold with units of magnetic field, e.g. "50µT"  \
`relativeAmplitudeAcccuracy`, defined as the allowable deviation of the amplitude as a ratio of the desired amplitude, e.g. 0.001

**Old parameter:**  \
`fieldToVoltDeviation`  \
**Replaced by:**  \
`fieldToVoltAbsDeviation`, absolute threshhold for how much the actual field amplitude is allowed to vary from the expected value in units of magnetic field, to still accept the system as safe, e.g. "5mT"  
`fieldToVoltRelDeviation`, relative threshhold for allowed deviation  
*Values will be used as rtol and atol of `isapprox`*

**Old parameter:**  \
`controlPause`  \
**Replaced by:**  \
`timeUntilStable`, time in s to wait before evaluating the feedback signals after ramping

**Changed parameters:**  \
`phaseAccuracy`, is now a Unitful value, specify e.g. "0.1°"

**Removed parameters:**  \
`correctCrossCoupling`, if a field has `decouple = true` the controller will correct the cross coupling


#### Calibrations
Because the feedback calibration (or transfer function) is now a complex value it is possible to include the phase shift between feedback and field into this number. This allows the field phase in the Sequence.toml to be set to the desired/nominal value ("0.0rad" or "sin" for sine excitation and "pi/2*rad" or "cos" for cosine excitation) instead of correcting for the feedback phase shift using that phase value.