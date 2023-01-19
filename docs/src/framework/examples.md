# Examples
## Magnetic Particle Spectroscopy (MPS)
The following is an example setup of an MPS system based on a RedPitaya StemLab 125-14. It has the following configuration directory:
```
MPS/
├── Sequences/
│   └── MPSSequence.toml
├── Protocols/
│   └── MPSProtocol.toml
└── Scanner.toml
```
It features two `Devices`: the `RedPitayaDAQ` device, which is responsible for signal generation and acquisition, and a virtual `Device` called `TxDAQController`. The latter `Device` is responsible for checking the amplitude and phase of channels that require control and iteratively improving them until the deviation has fallen below a given threshold.

The `RedPitayaDAQ` features one transmit channel `excitation` and two receive channel `rx_main` and `feedback_main`. The transmit channel is configured with calibration values, both for itself and for the feedback channel it is associated with. All channel are mapped to the channel of the Red Pitaya hardware.

To perform an MPS experiement one can use the `MPIMeasurementProtocol`, which takes a background and a foreground measurement and is capable of storing both in an MDF.
### Scanner.toml
```toml
[General]
boreSize = "6mm"
facility = "Universitätsklinikum Hamburg-Eppendorf"
manufacturer = "IBI"
name = "MPS"
topology = "MPS"
gradient = "0T/m"

[Runtime]
datasetStore = "/opt/data/MPS"
defaultProtocol = "MPSMeasurement"
producerThreadID = 2
consumerThreadID = 3
protocolThreadID = 4

[Devices]
initializationOrder = [
  "txController",
  "rp_cluster"
]

[Devices.rp_cluster]
deviceType = "RedPitayaDAQ"
dependencies = ["txController"]
ips = ["192.168.1.100"]
rampingMode = "STARTUP"
rampingFraction = 0.2
triggerMode = "INTERNAL"

[Devices.rp_cluster.excitation]
type = "tx"
channel = 1
limitPeak = "1.0V"
sinkImpedance = "HIGH"
calibration = "20.5V/T"
feedback.channelID = "feedback_main"
feedback.calibration = "0.017T/V"

[Devices.rp_cluster.rx_main]
type = "rx"
channel = 1

[Devices.rp_cluster.feedback_main]
type = "rx"
channel = 2

[Devices.txController]
deviceType = "TxDAQController"
dependencies = ["rp_cluster"]
phaseAccuracy = 0.1
amplitudeAccuracy = 0.01
maxControlSteps = 10
```
### MPSProtocol.toml
```toml
type = "MPIMeasurementProtocol"
description = "Default measurement protocol for the MPS scanner. Acquires a background and forground measurement"
targetScanner = "MPS"

sequence = "MPSSequence"
controlTx = true
fgFrames = 10
bgFrames = 10
```
### MPSSequence.toml
```toml
[General]
name = "MPSSequence"
description = "A sequence with a 26.042 kHz excitation frequency."
targetScanner = "MPS"
baseFrequency = "125.0MHz"

[Fields]

[Fields.ex]
safeStartInterval = "0.1s"
safeEndInterval = "0.1s"
safeErrorInterval = "0.1s"
control = true
decouple = false

[Fields.ex.excitation]
offset = "0.0mT"

[Fields.ex.excitation.c1]
divider = 4800
amplitude = ["20mT"]
phase = ["0.0rad"]
waveform = "sine"

[Acquisition]
channels = ["rx_main"]
bandwidth = "3.90625MHz"
numPeriodsPerFrame = 1
numFrames = 1
numAverages = 1000
numFrameAverages = 1
```