# Field camera — Porridge workflow

This document describes the end-to-end workflow to power coils on the Porridge field generator, measure the resulting magnetic field with the Arduino-based spherical sensor array (field camera), and run the student's post-processing to map measured frames to sequence timing.

Prerequisites
- Red Pitaya DAQ and amplifier wired to coils and reachable on the network.
- Arduino field-camera connected and operational; `sensorFolder` in scanner config must point to the `communicationSerialWithArduino` folder inside the `spericalsensor_ba-janne_hamann` project.
- Julia environment: run with `julia --project=.` from the `MPIMeasurementsPorridge` repository root.

Key files
- Adapter: `src/Devices/GaussMeter/FieldCameraAdapter.jl`
- Protocol: `src/Protocols/PorridgeFieldMeasurementProtocol.jl` (contains automatic postprocessing hook)
- Two-coil test sequence: `config/PorridgeFieldCamera/Sequences/TwoCoilTest.toml`
- Example scripts: `example/VerifySetup.jl`, `example/MinimalExample.jl`, `example/PostprocessFieldCamera.jl`
- Student code: `spericalsensor_ba-janne_hamann/communicationSerialWithArduino`

Quick start
1. Verify scanner config points to the student code folder. In `config/PorridgeFieldCamera/Scanner.toml` set:

   - `Devices.field_camera.deviceType = "FieldCameraAdapter"`
   - `Devices.field_camera.sensorFolder = "<full path to>/spericalsensor_ba-janne_hamann/communicationSerialWithArduino"`

2. Run the setup checks:
```powershell
julia --project=. example/VerifySetup.jl
```

3. Run a minimal measurement to confirm end-to-end behavior:
```powershell
julia --project=. example/MinimalExample.jl
```

4. Run the two-coil test sequence (example runner or call the protocol with `TwoCoilTest.toml`). The sequence file is at `config/PorridgeFieldCamera/Sequences/TwoCoilTest.toml` and contains three frames:
   - Frame 1: baseline (0 A)
   - Frame 2: coil1 and coil2 at 0.5 A
   - Frame 3: baseline (0 A)

Postprocessing (automatic)
- After saving a measurement (HDF5), the protocol attempts automatic postprocessing if it can locate the student's `postprocessing.jl` script.
- The protocol looks for `postprocessing.jl` at `../SteuerungPostProcessing/postprocessing.jl` relative to the configured `sensorFolder`.
- If found, the protocol will:
  1. Read `/sensorData` from the HDF5 file (3 × numSensors × numMeasurements).
  2. Convert frames to Unitful `Tesla` arrays and call `postprocessing(frames, sens_vec, sum_sensors)` from the student's script.
  3. Write the returned `t_start` and `t_k` arrays into the HDF5 under `/postprocessing/t_start` and `/postprocessing/t_k`.

Manual postprocessing
- Alternatively run:
```powershell
julia --project=. example/PostprocessFieldCamera.jl path\to\measurement.h5
```

How to change current sequences (two-coil example)
- Create a new sequence TOML under `config/PorridgeFieldCamera/Sequences` — copy `TwoCoilTest.toml` and adapt coil entries.
- Map logical channel names to physical outputs in `config/PorridgeFieldCamera/Scanner.toml` (ElectricalSource mapping). Verify which `coil1` / `coil2` correspond to your physical coil outputs.
- Start with low currents (e.g., 0.1 A) and use `VerifySetup.jl` and `MinimalExample.jl` to validate.

Tips and troubleshooting
- If no postprocessing occurs: check `sensorFolder` and that `SteuerungPostProcessing/postprocessing.jl` exists next to it.
- If timestamps or frames appear misaligned: increase `stabilizationTime` in `PorridgeFieldMeasurementProtocolParams`.
- If sensor CSV parsing fails (adapter falls back to per-sensor queries), consider adding the student's CSV patterns into the adapter parser.

Next steps (optional)
- Add a dedicated example runner that selects `TwoCoilTest.toml` and stores the measurement filename to a predictable location.
- Improve CSV parsing in `FieldCameraAdapter.jl` with robust handling of the student's measurement outputs.

Contact
- If you want, I can create the example runner and wire it to `TwoCoilTest.toml`, or extend the adapter's parsing logic to handle the sample CSVs in `communicationSerialWithArduino/MessungSensorarray/`.
