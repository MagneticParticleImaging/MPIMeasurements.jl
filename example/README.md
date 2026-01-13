# Field Camera Measurement Examples

Quick reference for field measurement scripts.

## Getting Started

**First time setup:**
```bash
# 1. Verify everything is configured correctly
julia --project=. example/VerifySetup.jl

# 2. Run your first measurement  
julia -t 4 --project=. example/MinimalExample.jl

# 3. Check the results
julia --project=. example/InspectFieldData.jl ./DataStore/measurement_*.h5
```

## Available Scripts

### Measurements

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `MinimalExample.jl` | Quick 10-measurement test | First run, quick tests |
| `FullFieldMeasurement.jl` | Full-featured with detailed progress | Production measurements |
| `VerifySetup.jl` | Check configuration | Before first run, troubleshooting |

### Data Analysis

| Script | Purpose | Output |
|--------|---------|--------|
| `InspectFieldData.jl` | View measurement statistics | Text summary to console |
| `ExportFieldData.jl` | Export to CSV | CSV file for Python/MATLAB |

### Debug Tools

| Script | Purpose |
|--------|---------|
| `debug/test_arduino.jl` | Test Arduino connection and firmware |
| `debug/test_sensor_query.jl` | Test sensor query commands |

## Quick Commands

**Run a measurement:**
```bash
julia -t 4 --project=. example/MinimalExample.jl
```

**Inspect results:**
```bash
julia --project=. example/InspectFieldData.jl ./DataStore/measurement_20260113_174116.h5
```

**Export to CSV:**
```bash
julia --project=. example/ExportFieldData.jl ./DataStore/measurement_20260113_174116.h5
```

## Common Issues

**"Arduino not found"**
- Run `julia --project=. example/debug/test_arduino.jl` to diagnose
- Check `/dev/ttyACM0` exists (Linux) or COM port (Windows)

**"No measurement files"**
- Files are in `./DataStore/` directory
- Check console for "Saved to:" message

**"Threading error"**
- Always use 4 threads: `julia -t 4 --project=.`

## Next Steps

- 📖 Read the full guide: [docs/FieldCameraWorkflow.md](../docs/FieldCameraWorkflow.md)
- ⚙️ Customize sequences: [config/PorridgeFieldCamera/Sequences/](../config/PorridgeFieldCamera/Sequences/)
- 🔧 Adjust settings: [config/PorridgeFieldCamera/Scanner.toml](../config/PorridgeFieldCamera/Scanner.toml)
