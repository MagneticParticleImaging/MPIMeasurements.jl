"""
# Porridge Field Measurement Example

This script demonstrates how to use the Porridge field generator with
flexible measurement devices (field camera or gauss meter) using the
unified PorridgeFieldMeasurementProtocol.

## Overview

The implementation provides a clean, holistic solution for:
1. Powering coils in the Porridge field generator
2. Measuring the resulting magnetic field
3. Supporting both field cameras and traditional gauss meters
4. Post-processing with spherical harmonics (for field cameras)

## Setup

Make sure you have the following:
- MPIMeasurements package installed
- Porridge scanner configured and accessible
- Field camera (Arduino-based) or gauss meter connected
- Appropriate COM port configured in Scanner.toml

"""

using MPIMeasurements
using Unitful
using HDF5

# =============================================================================
# Example 1: Field Measurement with Arduino Field Camera
# =============================================================================

println("=" ^ 80)
println("Example 1: Measuring with Arduino Field Camera")
println("=" ^ 80)

# Initialize scanner with field camera
scanner = MPIScanner("PorridgeFieldCamera", robust=true)

# Get the field camera device
fieldCamera = getGaussMeter(scanner)
println("Field camera device: $(typeof(fieldCamera))")
println("Number of sensors: $(fieldCamera.params.numSensors)")
println("Measurement range: $(fieldCamera.currentRange)mT")

# Load the measurement protocol
protocol = Protocol("PorridgeFieldMeasurement", scanner)
println("\nProtocol loaded: $(name(protocol))")
println("Description: $(description(protocol))")
println("Estimated time: $(timeEstimate(protocol))")

# Initialize protocol
init(protocol)

# Execute the measurement
println("\nStarting field measurement...")
biChannel = execute(protocol, scanner.generalParams.protocolThreadID)

if !isnothing(biChannel)
    # Monitor progress
    while true
        # Query progress
        put!(biChannel, ProgressQueryEvent())
        
        # Wait for events
        sleep(1.0)
        
        # Check for completion
        if isready(biChannel)
            event = take!(biChannel)
            
            if isa(event, ProgressEvent)
                progress = event.done / event.total * 100
                println("Progress: $(round(progress, digits=1))% ($(event.done)/$(event.total) frames)")
            elseif isa(event, FinishedNotificationEvent)
                println("\nMeasurement finished!")
                
                # Save data
                filename = "porridge_field_measurement_$(Dates.format(now(), "yyyymmdd_HHMMSS")).h5"
                put!(biChannel, FileStorageRequestEvent(filename))
                
                # Wait for save confirmation
                saveEvent = take!(biChannel)
                if isa(saveEvent, StorageSuccessEvent)
                    println("Data saved to: $filename")
                end
                
                # Acknowledge finish
                put!(biChannel, FinishedAckEvent())
                break
            elseif isa(event, ExceptionEvent)
                println("Error occurred: $(event.exception)")
                break
            end
        end
    end
end

# Cleanup
cleanup(protocol)
close(scanner)

println("\nExample 1 complete!")

# =============================================================================
# Example 2: Field Measurement with Traditional Gauss Meter
# =============================================================================

println("\n" * "=" ^ 80)
println("Example 2: Measuring with Traditional Gauss Meter")
println("=" ^ 80)

# This example assumes you have a gauss meter configured
# (e.g., LakeShore, MagSphere) in your Scanner.toml

# Initialize scanner (using standard Porridge configuration)
scanner2 = MPIScanner("Porridge", robust=true)

# Check which gauss meter is available
gaussMeter = getGaussMeter(scanner2)
println("Gauss meter device: $(typeof(gaussMeter))")

# Load protocol (same protocol works with different measurement devices!)
protocol2 = Protocol("PorridgeFieldMeasurement", scanner2)
println("\nProtocol loaded: $(name(protocol2))")

# The rest follows the same pattern as Example 1
# Initialize, execute, monitor, and save

init(protocol2)
println("Protocol initialized and ready to execute")

# Note: For brevity, we're not repeating the full execution here
# The pattern is identical to Example 1

close(scanner2)

println("\nExample 2 setup complete!")

# =============================================================================
# Example 3: Direct Device Access for Custom Measurements
# =============================================================================

println("\n" * "=" ^ 80)
println("Example 3: Direct Device Access")
println("=" ^ 80)

# Sometimes you want direct control without a protocol
scanner3 = MPIScanner("PorridgeFieldCamera", robust=true)
fieldCamera3 = getGaussMeter(scanner3)
daq = getDAQ(scanner3)

println("Performing single-point measurement...")

# Enable the field camera
enable(fieldCamera3)

# Set up a simple DC field using DAQ
# (This requires a sequence - see Example 4)

# Wait for measurement
sleep(2.0)

# Get data
if isready(fieldCamera3.ch)
    result = take!(fieldCamera3.ch)
    println("Timestamp: $(result.timestamp)")
    println("Data shape: $(size(result.data))")
    println("Mean field magnitude: $(mean(sqrt.(sum(result.data.^2, dims=1))))")
end

# Disable device
disable(fieldCamera3)
close(scanner3)

println("\nExample 3 complete!")

# =============================================================================
# Example 4: Processing Saved Data
# =============================================================================

println("\n" * "=" ^ 80)
println("Example 4: Post-Processing Saved Data")
println("=" ^ 80)

# Load and analyze data from a previous measurement
# (This assumes you have a measurement file from Example 1)

function processFieldCameraMeasurement(filename::String)
    if !isfile(filename)
        println("File not found: $filename")
        return
    end
    
    h5open(filename, "r") do file
        # Read basic info
        numMeasurements = read(file, "/numMeasurements")
        numSensors = read(file, "/numSensors")
        
        println("Loaded measurement with:")
        println("  - $numMeasurements frames")
        println("  - $numSensors sensors")
        
        # Read sensor data (3 x numSensors x numMeasurements)
        sensorData = read(file, "/sensorData")
        timestamps = read(file, "/timestamps")
        
        println("  - Time span: $(timestamps[end] - timestamps[1]) seconds")
        
        # Calculate field statistics
        fieldMagnitudes = sqrt.(sum(sensorData.^2, dims=1))
        avgField = mean(fieldMagnitudes)
        stdField = std(fieldMagnitudes)
        
        println("  - Average field: $(avgField*1000) mT")
        println("  - Field std dev: $(stdField*1000) mT")
        
        # Check if spherical harmonics were computed
        if haskey(file, "/sphericalHarmonics")
            println("  - Spherical harmonics coefficients available")
            tOrder = read(file, "/sphericalHarmonics/tDesignOrder")
            println("    T-Design order: $tOrder")
        end
    end
end

# Example usage (uncomment when you have data):
# processFieldCameraMeasurement("porridge_field_measurement_20260106_120000.h5")

println("\nExample 4 complete!")

# =============================================================================
# Example 5: Custom Sequence for Specific Coil Patterns
# =============================================================================

println("\n" * "=" ^ 80)
println("Example 5: Creating Custom Field Patterns")
println("=" ^ 80)

# This example shows how to create custom sequences for specific
# field patterns or coil configurations

# You would typically create a .toml sequence file in:
# config/PorridgeFieldCamera/Sequences/CustomPattern.toml

# Then use it with:
# protocol_params = Dict(
#     "sequence" => "CustomPattern",
#     "numMeasurementsPerPoint" => 20,
#     "stabilizationTime" => "1.0s"
# )

println("To create custom field patterns:")
println("1. Define a sequence in .toml format")
println("2. Specify coil currents and timing")
println("3. Load with Protocol('PorridgeFieldMeasurement', scanner)")
println("4. Execute and measure")

println("\nExample 5 complete!")

# =============================================================================
# Summary
# =============================================================================

println("\n" * "=" ^ 80)
println("Summary: Key Features")
println("=" ^ 80)
println("""
✓ Unified protocol works with field cameras AND traditional gauss meters
✓ Clean separation between field generation (DAQ) and measurement (GaussMeter)
✓ Automatic spherical harmonics processing for field cameras
✓ Flexible configuration via .toml files
✓ Easy to extend with new measurement devices
✓ Full integration with MPIMeasurements framework
✓ Comprehensive data storage in HDF5 format

Next Steps:
1. Adjust COM ports in Scanner.toml for your system
2. Create custom sequences for your specific experiments
3. Calibrate field camera if needed (update calibrationFile parameter)
4. Run measurements and analyze results!

For more information, see:
- Scanner configuration: config/PorridgeFieldCamera/Scanner.toml
- Protocol configuration: config/PorridgeFieldCamera/Protocols/PorridgeFieldMeasurement.toml
- Device implementation: src/Devices/GaussMeter/ArduinoFieldCamera.jl
- Protocol implementation: src/Protocols/PorridgeFieldMeasurementProtocol.jl
""")

println("=" ^ 80)
println("All examples complete!")
println("=" ^ 80)
