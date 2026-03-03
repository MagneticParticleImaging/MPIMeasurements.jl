# Generate 2D PDF plots using spherical-harmonics helper from spericalsensor repo.
# Usage: julia example/PlotFieldData.jl [path/to/measurement.h5]
#        (defaults to latest .h5 in DataStore/)
# NOTE: Run WITHOUT --project flag (activates student environment)

const ORIGINAL_DIR = pwd()

function find_latest_h5(dir::String)
    h5files = filter(f -> endswith(f, ".h5"), readdir(dir, join=true))
    isempty(h5files) && error("No .h5 files found in $dir")
    return h5files[argmax([mtime(f) for f in h5files])]
end

if length(ARGS) < 1
    # Default: use latest .h5 from DataStore/
    datastore = joinpath(ORIGINAL_DIR, "DataStore")
    if !isdir(datastore)
        println("Usage: julia example/PlotFieldDataOfficial2D.jl [path/to/measurement.h5]")
        println("       (defaults to latest .h5 in DataStore/)")
        println("       Run WITHOUT --project flag!")
        exit(1)
    end
    h5file = find_latest_h5(datastore)
    println("No file specified, using latest: $h5file")
else
    h5file = isabspath(ARGS[1]) ? ARGS[1] : joinpath(ORIGINAL_DIR, ARGS[1])
end

if !isfile(h5file)
    @error "File not found: $h5file"
    exit(1)
end

# default parameters (match messungSensorarray.jl)
Rmm = 37.0   # mm
t = 8
field_center = [0.0, 0.0, 0.0]

using Pkg
student_root = abspath(joinpath(homedir(), "repos", "spericalsensor_ba-janne_hamann"))
student_env = joinpath(student_root, "EnvMessungSensorarray")
if !isdir(student_env)
    @error "Student environment not found at: $student_env"
    exit(1)
end

cd(student_root)
Pkg.activate("EnvMessungSensorarray/")

using Plots
using Statistics
using HDF5

helper_path = abspath(joinpath(homedir(), "repos", "spericalsensor_ba-janne_hamann", "communicationSerialWithArduino", "processSphericalHarmonicsMeasurement.jl"))
if !isfile(helper_path)
    @error "Spherical harmonics helper not found at $helper_path"
    exit(1)
end

try
    include(helper_path)
catch e
    @error "Failed to load spherical harmonics helper" exception=e
    rethrow()
end

try
    using DelimitedFiles
    sensorData = nothing
    sensorPositions = nothing
    patchIndices = nothing
    h5open(h5file, "r") do f
        sensorData = read(f, "/sensorData")
        sensorPositions = read(f, "/sensorPositions")
        if haskey(f, "patchIndices")
            patchIndices = read(f, "/patchIndices")
        end
    end

    numMeasurements = size(sensorData, 3)
    N = size(sensorPositions, 2)
    baseName = splitext(basename(h5file))[1]
    outDir = dirname(h5file)

    println("Processing $numMeasurements measurement(s)...")

    for mIdx in 1:numMeasurements
        fieldSlice = sensorData[:, :, mIdx]

        csvData = Matrix{Any}(undef, N, 9)
        for i in 1:N
            csvData[i, 1] = i
            csvData[i, 2] = 0
            csvData[i, 3] = sensorPositions[1, i] / 1000.0
            csvData[i, 4] = sensorPositions[2, i] / 1000.0
            csvData[i, 5] = sensorPositions[3, i] / 1000.0
            csvData[i, 6] = sqrt(fieldSlice[1, i]^2 + fieldSlice[2, i]^2 + fieldSlice[3, i]^2)
            csvData[i, 7] = fieldSlice[1, i]
            csvData[i, 8] = fieldSlice[2, i]
            csvData[i, 9] = fieldSlice[3, i]
        end

        # Write IMTE-format CSV for spherical harmonics helper
        tmpcsv = joinpath(outDir, ".tmp_$(baseName)_m$(mIdx).csv")
        open(tmpcsv, "w") do io
            println(io, "Sensor-Pin; DateAndTime; X-Position; Y-Position; Z-Position; Betrag; X; Y; Z")
            writedlm(io, csvData, ';')
        end

        fieldMF = sphericalHarmonicsDefinedFieldFromIMTEMeasurementFile(tmpcsv; t=t, R=Rmm, center=field_center)

        coords = Base.range(-Rmm, Rmm, length=100)
        patchLabel = isnothing(patchIndices) ? "" : "_patch$(patchIndices[mIdx])"
        heatmapSphericalHarmonicsDefinedFieldInOrthogonalPlanesAtCoordinate(fieldMF, coords; bUnitModifier=1000)

        outpdf = joinpath(outDir, "official2D_$(baseName)_m$(mIdx)$(patchLabel).pdf")
        Plots.savefig(outpdf)
        println("  [$mIdx/$numMeasurements] Saved: $outpdf")

        rm(tmpcsv; force=true)
    end

    println("Done — generated $numMeasurements plot(s).")
catch e
    println("Failed to produce official 2D PDF: ", e)
    rethrow()
end
