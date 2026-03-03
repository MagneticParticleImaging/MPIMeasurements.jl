# Inspect field camera HDF5 measurement data.
# Usage: julia --project=. example/InspectFieldData.jl [path/to/measurement.h5]
#        (defaults to latest .h5 in DataStore/)

using HDF5
using Statistics
using LinearAlgebra

function inspect_field_data(h5_file::String)
  println("=" ^ 70)
  println("Field Camera Data Inspection: $h5_file")
  println("=" ^ 70)
  println()

  h5open(h5_file, "r") do f
    allkeys = sort(collect(keys(f)))
    println("Datasets:")
    for key in allkeys
      println("  $key")
    end
    println()

    if !haskey(f, "sensorData")
      println("No /sensorData found.")
      if haskey(f, "numMeasurements")
        println("  numMeasurements: $(read(f, "/numMeasurements"))")
      end
      return
    end

    sensorData = read(f, "/sensorData")
    numMeasurements = haskey(f, "numMeasurements") ? read(f, "/numMeasurements") : size(sensorData, 3)
    numSensors = haskey(f, "numSensors") ? read(f, "/numSensors") : size(sensorData, 2)

    println("Dimensions:")
    println("  Sensors:      $numSensors")
    println("  Measurements: $numMeasurements")
    println("  Data shape:   $(size(sensorData))")
    println()

    # Field statistics (averaged over all measurements)
    avgField = mean(sensorData, dims=3)[:, :, 1]

    println("Field Statistics (average over $numMeasurements measurements):")
    for (idx, comp) in enumerate(["X", "Y", "Z"])
      d = avgField[idx, :]
      println("  $comp: min=$(round(minimum(d)*1000, digits=3)) mT, " *
              "max=$(round(maximum(d)*1000, digits=3)) mT, " *
              "mean=$(round(mean(d)*1000, digits=3)) mT, " *
              "std=$(round(std(d)*1000, digits=3)) mT")
    end

    mags = [norm(avgField[:, i]) for i in 1:numSensors]
    println("  |B|: min=$(round(minimum(mags)*1000, digits=3)) mT, " *
            "max=$(round(maximum(mags)*1000, digits=3)) mT, " *
            "mean=$(round(mean(mags)*1000, digits=3)) mT")
    println()

    # Per-measurement breakdown
    if numMeasurements > 1
      patchIndices = haskey(f, "patchIndices") ? read(f, "/patchIndices") : nothing
      println("Per-measurement field magnitudes:")
      for m in 1:numMeasurements
        frame = sensorData[:, :, m]
        frameMags = [norm(frame[:, i]) for i in 1:numSensors]
        pLabel = isnothing(patchIndices) ? "" : " (patch $(patchIndices[m]))"
        println("  Measurement $m$pLabel: |B| mean=$(round(mean(frameMags)*1000, digits=3)) mT, " *
                "max=$(round(maximum(frameMags)*1000, digits=3)) mT")
      end
      println()
    end

    # Sensor positions
    if haskey(f, "sensorPositions")
      positions = read(f, "/sensorPositions")
      println("Sensor positions range (mm):")
      for (idx, axis) in enumerate(["X", "Y", "Z"])
        p = positions[idx, :]
        println("  $axis: $(round(minimum(p), digits=1)) to $(round(maximum(p), digits=1))")
      end
      println()
    end

    # Timing
    if haskey(f, "timestamps")
      timestamps = read(f, "/timestamps")
      println("Timing:")
      println("  First: $(timestamps[1]) s")
      println("  Last:  $(timestamps[end]) s")
      if length(timestamps) > 1
        println("  Duration: $(round(timestamps[end] - timestamps[1], digits=2)) s")
        println("  Avg interval: $(round(mean(diff(timestamps)), digits=3)) s")
      end
    end

    # Frame metadata
    if haskey(f, "frameIndices") && haskey(f, "coilCurrents") && haskey(f, "coilNames")
      println()
      println("Frame metadata:")
      frameIndices = read(f, "/frameIndices")
      coilCurrents = read(f, "/coilCurrents")
      coilNames = read(f, "/coilNames")

      println("  Frames: $(length(frameIndices))")
      if haskey(f, "patchIndices")
        patchIndices = read(f, "/patchIndices")
        println("  Patches: $(unique(patchIndices))")
      end
      for (i, name) in enumerate(coilNames)
        currents = coilCurrents[:, i]
        any(currents .!= 0) || continue
        println("  $name: $(round(minimum(currents), digits=3)) – $(round(maximum(currents), digits=3)) A")
      end
    end
  end

  println()
  println("=" ^ 70)
end

function find_latest_h5(dir::String)
  h5files = filter(f -> endswith(f, ".h5"), readdir(dir, join=true))
  isempty(h5files) && error("No .h5 files found in $dir")
  return argmax(mtime, h5files)
end

# Main
if length(ARGS) < 1
  inspect_field_data(find_latest_h5("DataStore"))
else
  inspect_field_data(ARGS[1])
end
