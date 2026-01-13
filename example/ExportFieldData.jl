"""
Export HDF5 data to CSV for visualization in other tools
"""

using HDF5
using DelimitedFiles
using Statistics
using LinearAlgebra

function export_to_csv(h5_file::String)
    base = splitext(h5_file)[1]
    
    h5open(h5_file, "r") do f
        sensorData = read(f, "/sensorData")
        sensorPositions = read(f, "/sensorPositions")
        
        # Average field
        avgField = mean(sensorData, dims=3)[:, :, 1]
        
        # Magnitude
        magnitude = [norm(avgField[:, i]) * 1000 for i in 1:size(avgField, 2)]
        
        # Export: X, Y, Z (positions in mm), Bx, By, Bz, |B| (fields in mT)
        export_data = hcat(
            sensorPositions',
            (avgField * 1000)',
            magnitude
        )
        
        csv_file = base * "_export.csv"
        writedlm(csv_file, 
                 vcat(["X_mm" "Y_mm" "Z_mm" "Bx_mT" "By_mT" "Bz_mT" "B_magnitude_mT"],
                      export_data), 
                 ',')
        
        println("✓ Exported to: $csv_file")
        println("Columns: X, Y, Z (mm), Bx, By, Bz, |B| (mT)")
        println("Use Python/MATLAB/Excel to visualize")
    end
end

if length(ARGS) > 0
    export_to_csv(ARGS[1])
else
    println("Usage: julia --project=. example/ExportFieldData.jl path/to/file.h5")
end
