"""
Quick inspection of field camera HDF5 data

Usage: julia --project=. example/InspectFieldData.jl path/to/measurement.h5
"""

using HDF5
using Statistics
using LinearAlgebra

function inspect_field_data(h5_file::String)
    println("="^80)
    println("Field Camera Data Inspection")
    println("="^80)
    println("File: $h5_file")
    println()
    
    h5open(h5_file, "r") do f
        # List all datasets
        println("📊 Datasets:")
        for key in sort(collect(keys(f)))
            println("  - $key")
        end
        println()
        
        # Read data
        sensorData = read(f, "/sensorData")
        sensorPositions = read(f, "/sensorPositions")
        timestamps = read(f, "/timestamps")
        numMeasurements = read(f, "/numMeasurements")
        numSensors = read(f, "/numSensors")
        
        println("📏 Dimensions:")
        println("  - Sensors: $numSensors")
        println("  - Measurements: $numMeasurements")
        println("  - Sensor data shape: $(size(sensorData))")
        println("  - Sensor positions shape: $(size(sensorPositions))")
        println()
        
        # Field statistics
        println("🧲 Field Statistics (averaged over all measurements):")
        avgField = mean(sensorData, dims=3)[:, :, 1]
        
        for (idx, comp) in enumerate(["X", "Y", "Z"])
            componentData = avgField[idx, :]
            println("  $comp-component:")
            println("    Min:  $(round(minimum(componentData)*1000, digits=3)) mT")
            println("    Max:  $(round(maximum(componentData)*1000, digits=3)) mT")
            println("    Mean: $(round(mean(componentData)*1000, digits=3)) mT")
            println("    Std:  $(round(std(componentData)*1000, digits=3)) mT")
        end
        
        magnitudes = [norm(avgField[:, i]) for i in 1:numSensors]
        println("  Magnitude:")
        println("    Min:  $(round(minimum(magnitudes)*1000, digits=3)) mT")
        println("    Max:  $(round(maximum(magnitudes)*1000, digits=3)) mT")
        println("    Mean: $(round(mean(magnitudes)*1000, digits=3)) mT")
        println()
        
        # Sensor positions
        println("📍 Sensor Position Range:")
        for (idx, axis) in enumerate(["X", "Y", "Z"])
            positions = sensorPositions[idx, :]
            println("  $axis: $(round(minimum(positions), digits=1)) to $(round(maximum(positions), digits=1)) mm")
        end
        println()
        
        # Timing info
        println("⏱️  Timing:")
        println("  - First timestamp: $(timestamps[1]) s")
        println("  - Last timestamp:  $(timestamps[end]) s")
        if length(timestamps) > 1
            println("  - Duration: $(round(timestamps[end] - timestamps[1], digits=2)) s")
            println("  - Avg interval: $(round(mean(diff(timestamps)), digits=3)) s")
        end
        
        # Optional postprocessing data
        if haskey(f, "postprocessing")
            println()
            println("🔬 Postprocessing data found:")
            pp = f["postprocessing"]
            for key in keys(pp)
                println("  - $key: $(size(read(pp, key)))")
            end
        end
    end
    
    println()
    println("="^80)
end

# Main
if length(ARGS) < 1
    println("Usage: julia --project=. example/InspectFieldData.jl path/to/measurement.h5")
else
    inspect_field_data(ARGS[1])
end
