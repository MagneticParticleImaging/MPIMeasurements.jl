# Field Camera Workflow — Quick Guide

Complete guide for running magnetic field measurements with the Arduino spherical sensor array and Porridge coil system.

## Prerequisites

✓ **Hardware:**
- Arduino field camera connected to `/dev/ttyACM0` (Linux) or `COM3` (Windows)
- Red Pitaya DAQ cluster (9 units) connected and reachable on network
- Firmware uploaded to Arduino from `spericalsensor_ba-janne_hamann/communicationSerialWithArduino/serialCommunicationWithJulia/`

✓ **Software:**
- Julia 1.10+ with 4 threads: `julia -t 4 --project=.`
- Student code folder: `spericalsensor_ba-janne_hamann/communicationSerialWithArduino/`

## Quick Start (3 Steps)

### 1. Verify Setup
```bash
julia --project=. example/VerifySetup.jl
```
This checks scanner configuration and device availability.

### 2. Run Measurement
```bash
julia -t 4 --project=. example/MinimalExample.jl
```
Runs a simple 2-coil test with 10 measurements per point. Data saved to `./DataStore/`.

### 3. Inspect Results
```bash
julia --project=. example/InspectFieldData.jl ./DataStore/measurement_YYYYMMDD_HHMMSS.h5
```
Shows complete field statistics and timing information.

## Available Scripts

**Measurements:**
- `example/MinimalExample.jl` - Quick test measurement (recommended first run)
- `example/FullFieldMeasurement.jl` - Full-featured with progress tracking and detailed output

**Data Analysis:**
- `example/InspectFieldData.jl` - Text-based data inspection (works everywhere)
- `example/ExportFieldData.jl` - Export to CSV for Python/MATLAB visualization

**Debug:**
- `example/debug/test_arduino.jl` - Test Arduino communication
- `example/debug/test_sensor_query.jl` - Test sensor query commands

## Configuration

### Scanner Config
Edit `config/PorridgeFieldCamera/Scanner.toml`:
```toml
[Devices.field_camera]
deviceType = "FieldCameraAdapter"
sensorFolder = "/absolute/path/to/spericalsensor_ba-janne_hamann/communicationSerialWithArduino"
portAddress = "/dev/ttyACM0"  # or "COM3" on Windows
measurementRange = 150  # mT (options: 75, 150, 300)
numSensors = 37
```

### Protocol Config
Edit `config/PorridgeFieldCamera/Protocols/PorridgeFieldMeasurement.toml`:
```toml
sequence = "TwoCoilTest"
numMeasurementsPerPoint = 10  # Increase for better averaging
stabilizationTime = "0.5s"  # Wait time between coil change and measurement
enableSphericalHarmonics = true  # Requires MPISphericalHarmonics package
```

### Sequence Config
Edit `config/PorridgeFieldCamera/Sequences/TwoCoilTest.toml` to customize:
- Coil currents (values)
- Field patterns
- Number of frames

Example: Change coil current from 0.99A to 1.5A:
```toml
[Fields.cage2.coil12]
values = ["1.5A"]  # Was ["0.99A"]
```

## Data Structure

Measurement files (HDF5) contain:
- `/sensorData` - 3 × 37 × N array (X,Y,Z components, 37 sensors, N measurements)
- `/sensorPositions` - 3 × 37 array (sensor positions in mm)
- `/timestamps` - Measurement timestamps
- `/numMeasurements`, `/numSensors` - Metadata

## Common Workflows

### Quick Field Check
```bash
# Run minimal test
julia -t 4 --project=. example/MinimalExample.jl

# Inspect results
julia --project=. example/InspectFieldData.jl ./DataStore/measurement_*.h5
```

### Production Measurement
1. Create custom sequence in `config/PorridgeFieldCamera/Sequences/`
2. Update protocol config to reference it
3. Run: `julia -t 4 --project=. example/FullFieldMeasurement.jl`
4. Export for analysis: `julia --project=. example/ExportFieldData.jl ./DataStore/measurement_*.h5`

### Export for External Tools
```bash
# Export to CSV
julia --project=. example/ExportFieldData.jl ./DataStore/measurement_YYYYMMDD_HHMMSS.h5

# Then visualize in Python:
# import pandas as pd; import matplotlib.pyplot as plt
# data = pd.read_csv('DataStore/measurement_YYYYMMDD_HHMMSS_export.csv')
# plt.scatter(data['X_mm'], data['Y_mm'], c=data['B_magnitude_mT'])
```

## Troubleshooting

**Arduino not found:**
- Check connection: `ls /dev/ttyACM*` (Linux) or Device Manager (Windows)
- Test firmware: `julia --project=. example/debug/test_arduino.jl`
- Verify baud rate: 74880 (non-standard, requires exact match)

**CRC errors from sensors:**
- Normal for some sensors (1, 14-21) - hardware issue
- Measurements still valid (zeros for bad sensors)
- Errors suppressed in logs (debug level only)

**No measurement files:**
- Check `./DataStore/` directory exists (auto-created)
- Look for "Saved to:" message in output
- Verify HDF5 write completed (protocol shows "async save task")

**Threading issues:**
- Always run with 4 threads: `julia -t 4 --project=.`
- Protocol uses thread 3, HDF5 on :interactive pool
- Don't reduce thread count below 4

## Advanced: Spherical Harmonics

**Setup (optional):**
```bash
cd ~/repos/spericalsensor_ba-janne_hamann/communicationSerialWithArduino
julia createEnvMessungSensorarray.jl
```

This installs `MPISphericalHarmonics` and `MPIMagneticFields` for advanced field analysis.

Enable in protocol config:
```toml
enableSphericalHarmonics = true
tDesignOrder = 12
sphericalRadius = "45mm"
```

## Key Files Reference

**Core Implementation:**
- Adapter: [src/Devices/GaussMeter/FieldCameraAdapter.jl](src/Devices/GaussMeter/FieldCameraAdapter.jl)
- Protocol: [src/Protocols/PorridgeFieldMeasurementProtocol.jl](src/Protocols/PorridgeFieldMeasurementProtocol.jl)

**Student Code (External):**
- Sensor control: `spericalsensor_ba-janne_hamann/communicationSerialWithArduino/serialCommunicationDeviceArduino.jl`
- Arduino firmware: `spericalsensor_ba-janne_hamann/communicationSerialWithArduino/serialCommunicationWithJulia/`

**Configuration:**
- Scanner: [config/PorridgeFieldCamera/Scanner.toml](config/PorridgeFieldCamera/Scanner.toml)
- Protocol: [config/PorridgeFieldCamera/Protocols/PorridgeFieldMeasurement.toml](config/PorridgeFieldCamera/Protocols/PorridgeFieldMeasurement.toml)
- Sequence: [config/PorridgeFieldCamera/Sequences/TwoCoilTest.toml](config/PorridgeFieldCamera/Sequences/TwoCoilTest.toml)
