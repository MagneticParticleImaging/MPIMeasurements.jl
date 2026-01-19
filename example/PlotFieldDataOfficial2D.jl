"""
Generate the provider-standard 2D PDF using the spherical-harmonics helper
from the other repository (if available).

Usage:
  julia --project=. example/PlotFieldDataOfficial2D.jl path/to/measurement.h5

This script will attempt to include the helper used in
`spericalsensor_ba-janne_hamann/communicationSerialWithArduino/messungSensorarray.jl`:
`processSphericalHarmonicsMeasurement.jl` which defines
`sphericalHarmonicsDefinedFieldFromIMTEMeasurementFile` and
`heatmapSphericalHarmonicsDefinedFieldInOrthogonalPlanesAtCoordinate`.
If that file is not found, the script prints instructions.
"""

using Plots
using Statistics
using HDF5

function usage()
    println("Usage: julia --project=. example/PlotFieldDataOfficial2D.jl path/to/measurement.h5")
end

if length(ARGS) < 1
    usage(); exit()
end

h5file = ARGS[1]
# default parameters (match messungSensorarray.jl)
Rmm = 37.0   # mm
t = 8
center = [0.0, 0.0, 0.0]

# try to include the helper from the spericalsensor repo
include(joinpath("..", "..", "spericalsensor_ba-janne_hamann", "communicationSerialWithArduino", "processSphericalHarmonicsMeasurement.jl"))

# At this point the helper should define the required functions
# Build the field and plot the official 2D PDF. Support direct HDF5 measurement files.
try
    if endswith(lowercase(h5file), ".h5") || endswith(lowercase(h5file), ".hdf5")
        # Read HDF5 measurement layout used in MPIMeasurementsPorridge
        using HDF5
        sensorData = nothing
        sensorPositions = nothing
        h5open(h5file, "r") do f
            sensorData = read(f, "/sensorData")   # 3 x N x M
            sensorPositions = read(f, "/sensorPositions") # 3 x N
        end
        # average over measurements (third dim)
        avgField = mean(sensorData, dims=3)[:, :, 1]
        # build point and field matrices expected by helper (points in mm, field in T)
        points = hcat(vec(sensorPositions[1, :]), vec(sensorPositions[2, :]), vec(sensorPositions[3, :]))
        field = hcat(vec(avgField[1, :]), vec(avgField[2, :]), vec(avgField[3, :]))
        fieldMF = sphericalHarmonicsDefinedFieldFromFieldData(points, field; t=t, R=Rmm, center=center)
    else
        fieldMF = sphericalHarmonicsDefinedFieldFromIMTEMeasurementFile(h5file; t=t, R=Rmm, center=center)
    end

    coords = Base.range(-Rmm, Rmm, length=100)
    heatmapSphericalHarmonicsDefinedFieldInOrthogonalPlanesAtCoordinate(fieldMF, coords; bUnitModifier=1000)
    outpdf = joinpath(dirname(h5file), "official2D_$(splitext(basename(h5file))[1]).pdf")
    # save via Plots.savefig as messungSensorarray.jl did
    Plots.savefig(outpdf)
    println("Saved official 2D PDF: ", outpdf)
catch e
    println("Failed to produce official 2D PDF: ", e)
    rethrow()
end
