# Porridge field measurement with the triggered MagSphere (MagSphereUDP)
#
# The staged protocol of GenerateData.jl, recorded with the 114-sensor MagSphere on its
# BNC trigger instead of the Arduino field camera (scanner config/PorridgeMagSphere,
# device `magsphere`: triggerMode = "external", ±240 mT).
#   - The RedPitaya "trigger" channel runs at TRIGGER_RATE_HZ = 100 Hz; the sphere sends
#     one frame per rising edge. In this mode the driver sends no start/stop commands.
#   - Every coil configuration (random draw, single-coil check) is held for
#     HOLD_TIME_S = 1 s, i.e. 100 frames.
#   - Backgrounds and the periodic-check interval keep their durations from the 25 Hz
#     run (40 s, ~33 min), so their frame counts are 4x larger and the run still takes ~6 h.
#   - Missed frames are detected in PorridgeMagSphereMeasurementProtocol from the
#     sphere's timestamps: a gap of k trigger periods means k - 1 lost frames, which are
#     stored as NaN placeholders so that frame i stays paired with the currents of trigger
#     edge i. This script shows the count with the progress and a summary at the end.

using MPIMeasurements
using Dates
using Random
using Unitful

# Make a single Ctrl+C throw InterruptException so the running measurement
# can be stopped cleanly and the partial data can still be saved.
Base.exit_on_sigint(false)

println("Starting Porridge MagSphere field measurement...")

const RIGHT_COIL_ORDER = [17, 3, 18, 14, 12, 16, 10, 11, 13]
const LEFT_COIL_ORDER = [9, 6, 8, 7, 15, 5, 4, 2, 1]

# Trigger rate = MagSphere frame rate. Must be one the sphere can follow (≤ 1 kHz, manual Sect. 1.3).
const TRIGGER_RATE_HZ = 100.0
# Each coil configuration is held this long before the next one is applied.
const HOLD_TIME_S = 1.0
const FRAMES_PER_CONFIGURATION = round(Int, TRIGGER_RATE_HZ * HOLD_TIME_S)

frames_for_seconds(seconds) = round(Int, seconds * TRIGGER_RATE_HZ)

const PRIMARY_BACKGROUND_MEASUREMENTS = frames_for_seconds(40.0)
const PRIMARY_RANDOM_PAIRS_PER_SIDE = 1000
const PRIMARY_RANDOM_CYCLES = 10 # number of times the "1000 pairs/side" R+L block is repeated
const PRIMARY_RANDOM_MAX_CURRENT_A = 0.95
const PRIMARY_SINGLE_COIL_MAX_CURRENT_A = 0.95
const PRIMARY_RANDOM_REPEATS_PER_PAIR = FRAMES_PER_CONFIGURATION
# Each coil of a single-coil check is held for one configuration, too. At 100 Hz a single
# frame (10 ms) would only see the current step itself.
const PRIMARY_SINGLE_COIL_FRAMES_PER_COIL = FRAMES_PER_CONFIGURATION
# Background frames inserted between the right-side and left-side block of every cycle,
# purely to make the block boundaries easier to pick out in the recorded stream. Set to 0
# to disable.
const PRIMARY_INTERBLOCK_BACKGROUND_MEASUREMENTS = frames_for_seconds(40.0)
# A single-coil check only brackets the run at start/end, so a coil that fails partway
# through leaves everything after it untrustworthy with no way to tell where the failure
# happened. Re-running the check every ~33 min bounds that uncertainty window instead of
# covering the whole run. Set to 0 to disable.
const PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES = frames_for_seconds(2000.0)
# The coil driver can source at most 150 A total, summed across all simultaneously active
# coils, in any single frame. This setup's normalized current scale maps -1..1 to -30..30 A,
# so the limit in these units is 150 / 30 = 5.0.
const MAX_TOTAL_COIL_CURRENT_UNITS = 150.0 / 30.0

function alternating_trigger_values(numMeasurements::Int)
    vals = zeros(Float64, 2 * numMeasurements)
    vals[1:2:end] .= 0.9
    return vals .* u"A"
end

function random_independent_right_coils(numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    return random_independent_coils(RIGHT_COIL_ORDER, numPairs; maxCurrent_A, repeatsPerPair)
end

function random_independent_left_coils(numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    return random_independent_coils(LEFT_COIL_ORDER, numPairs; maxCurrent_A, repeatsPerPair)
end

function random_independent_coils(coilIDs::AbstractVector{Int}, numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    repeatsPerPair >= 1 || throw(ArgumentError("repeatsPerPair must be >= 1"))
    n = length(coilIDs)
    baseValues = Dict(coilID => Vector{Float64}(undef, numPairs) for coilID in coilIDs)

    # Rejection sampling under the coil driver's total-current limit: redraw the whole
    # i.i.d. set until it satisfies the limit, so accepted draws keep their intended
    # distribution (no pile-up on the constraint boundary, no added correlation). See
    # GenerateData.jl for the full reasoning.
    draw = Vector{Float64}(undef, n)
    # Fails loudly if a config change makes the limit infeasible; the worst case of this
    # setup (18 coils, 0.95) needs > 100,000 attempts with probability ~2.8e-41.
    maxAttemptsPerPair = 100_000
    for pairIdx in 1:numPairs
        total = Inf
        attempts = 0
        while total > MAX_TOTAL_COIL_CURRENT_UNITS
            attempts += 1
            attempts > maxAttemptsPerPair &&
                throw(ErrorException("Could not draw a coil-current combination under the $(MAX_TOTAL_COIL_CURRENT_UNITS)-unit total-current limit within $maxAttemptsPerPair attempts; maxCurrent_A=$maxCurrent_A with $n active coils may make the limit infeasible or astronomically rare"))
            for i in 1:n
                draw[i] = (2 * rand() - 1) * maxCurrent_A
            end
            total = sum(abs, draw)
        end
        for (i, coilID) in enumerate(coilIDs)
            baseValues[coilID][pairIdx] = draw[i]
        end
    end

    coilCurrents = Dict{Int, Vector{Float64}}()
    for coilID in coilIDs
        coilCurrents[coilID] = repeat(baseValues[coilID], inner=repeatsPerPair)
    end
    return coilCurrents
end

function all_coils_zero_currents(numMeasurements::Int)
    return Dict(coilID => zeros(numMeasurements) for coilID in 1:18)
end

function append_currents_segment!(total::Dict{Int, Vector{Float64}}, segment::Dict{Int, Vector{Float64}})
    nMeasurements = isempty(segment) ? 0 : length(first(values(segment)))
    for coilID in 1:18
        pushSegment = get(segment, coilID, zeros(nMeasurements))
        append!(total[coilID], pushSegment)
    end
    return total
end

# Coil 1 alone for framesPerCoil frames, then coil 2 alone, ..., coil 18 alone.
function single_coil_check_segment(; maxCurrent_A::Float64=PRIMARY_SINGLE_COIL_MAX_CURRENT_A,
                                    framesPerCoil::Int=PRIMARY_SINGLE_COIL_FRAMES_PER_COIL)
    segment = all_coils_zero_currents(18 * framesPerCoil)
    for coilID in 1:18
        segment[coilID][(coilID - 1) * framesPerCoil + 1:coilID * framesPerCoil] .= maxCurrent_A
    end
    return segment
end

# Insert a single-coil check every `intervalFrames` frames throughout an already-built
# sequence, so a coil that fails mid-run is caught within one interval instead of only at
# the start/end checks. Checkpoints are computed against the pre-insertion frame count and
# applied back-to-front so earlier insertions don't shift the position of checkpoints still
# to be processed. The last `intervalFrames ÷ 4` frames are left alone since the run's own
# final check segment already covers that region.
function insert_periodic_single_coil_checks!(total::Dict{Int, Vector{Float64}}, intervalFrames::Int;
                                              maxCurrent_A::Float64=PRIMARY_SINGLE_COIL_MAX_CURRENT_A)
    intervalFrames <= 0 && return total
    totalFrames = isempty(total) ? 0 : length(first(values(total)))
    checkSegment = single_coil_check_segment(; maxCurrent_A)

    checkpoints = intervalFrames:intervalFrames:(totalFrames - intervalFrames ÷ 4)
    for checkpoint in Iterators.reverse(checkpoints)
        for coilID in 1:18
            splice!(total[coilID], (checkpoint + 1):checkpoint, checkSegment[coilID])
        end
    end
    return total
end

function build_primary_coil_currents(; backgroundMeasurements::Int=PRIMARY_BACKGROUND_MEASUREMENTS,
                                      randomPairsPerSide::Int=PRIMARY_RANDOM_PAIRS_PER_SIDE,
                                      randomCycles::Int=PRIMARY_RANDOM_CYCLES,
                                      maxCurrent_A::Float64=PRIMARY_RANDOM_MAX_CURRENT_A,
                                      singleCoilMaxCurrent_A::Float64=PRIMARY_SINGLE_COIL_MAX_CURRENT_A,
                                      repeatsPerPair::Int=PRIMARY_RANDOM_REPEATS_PER_PAIR,
                                      interBlockBackgroundMeasurements::Int=PRIMARY_INTERBLOCK_BACKGROUND_MEASUREMENTS,
                                      periodicCheckInterval_frames::Int=PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES)
    total = all_coils_zero_currents(0)

    # Initial background.
    append_currents_segment!(total, all_coils_zero_currents(backgroundMeasurements))

    # Quick per-coil amplifier checks.
    append_currents_segment!(total, single_coil_check_segment(; maxCurrent_A=singleCoilMaxCurrent_A))

    # Right-side block, then left-side block, then a background: randomPairsPerSide base pairs,
    # each held for repeatsPerPair consecutive measurements before moving to the next pair. The
    # trailing background just separates one right+left pair from the next in the stream; it is
    # not a calibration bracket like the initial/middle/final backgrounds.
    for _ in 1:randomCycles
        append_currents_segment!(total, random_independent_right_coils(randomPairsPerSide; maxCurrent_A, repeatsPerPair))
        append_currents_segment!(total, random_independent_left_coils(randomPairsPerSide; maxCurrent_A, repeatsPerPair))
        append_currents_segment!(total, all_coils_zero_currents(interBlockBackgroundMeasurements))
    end

    # Middle background before the combined 18-coil random block.
    append_currents_segment!(total, all_coils_zero_currents(backgroundMeasurements))

    # All 18 coils randomly driven together (the "double-sided"/simultaneous block). Deliberately
    # last among the data-collection segments, immediately before the closing background+check
    # bracket — it must stay last relative to the single-sided cycles above.
    append_currents_segment!(total, random_independent_coils(collect(1:18), randomPairsPerSide; maxCurrent_A, repeatsPerPair))

    # Final background.
    append_currents_segment!(total, all_coils_zero_currents(backgroundMeasurements))

    # Final per-coil amplifier checks.
    append_currents_segment!(total, single_coil_check_segment(; maxCurrent_A=singleCoilMaxCurrent_A))

    # Bound how far a mid-run coil failure can spread before it's caught, instead of only
    # checking at the very start/end.
    insert_periodic_single_coil_checks!(total, periodicCheckInterval_frames; maxCurrent_A=singleCoilMaxCurrent_A)

    return total
end

# Per-frame label vector for build_primary_coil_currents, built with the exact same
# segment order and periodic-splice logic (including insert_periodic_single_coil_checks!'s
# checkpoint formula), so frame index i in the actual current/measurement data can be
# looked up here to see what it is. Keep this in sync with build_primary_coil_currents;
# if that function's segment order changes, mirror the change here too.
function build_primary_frame_labels(; backgroundMeasurements::Int=PRIMARY_BACKGROUND_MEASUREMENTS,
                                     randomPairsPerSide::Int=PRIMARY_RANDOM_PAIRS_PER_SIDE,
                                     randomCycles::Int=PRIMARY_RANDOM_CYCLES,
                                     repeatsPerPair::Int=PRIMARY_RANDOM_REPEATS_PER_PAIR,
                                     interBlockBackgroundMeasurements::Int=PRIMARY_INTERBLOCK_BACKGROUND_MEASUREMENTS,
                                     periodicCheckInterval_frames::Int=PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES,
                                     checkFrames::Int=18 * PRIMARY_SINGLE_COIL_FRAMES_PER_COIL)
    labels = String[]
    append!(labels, fill("bg_initial", backgroundMeasurements))
    append!(labels, fill("coilcheck_initial", checkFrames))

    sideBlockFrames = randomPairsPerSide * repeatsPerPair
    for c in 1:randomCycles
        append!(labels, fill("cycle$(c)_right", sideBlockFrames))
        append!(labels, fill("cycle$(c)_left", sideBlockFrames))
        append!(labels, fill("cycle$(c)_interblock_bg", interBlockBackgroundMeasurements))
    end

    append!(labels, fill("bg_mid", backgroundMeasurements))
    append!(labels, fill("all18", sideBlockFrames))
    append!(labels, fill("bg_final", backgroundMeasurements))
    append!(labels, fill("coilcheck_final", checkFrames))

    if periodicCheckInterval_frames > 0
        totalFrames = length(labels)
        checkpoints = periodicCheckInterval_frames:periodicCheckInterval_frames:(totalFrames - periodicCheckInterval_frames ÷ 4)
        for checkpoint in Iterators.reverse(checkpoints)
            splice!(labels, (checkpoint + 1):checkpoint, fill("periodic_check", checkFrames))
        end
    end

    return labels
end

# Collapse a per-frame label vector (e.g. from build_primary_frame_labels()) into
# (label, firstIndex, lastIndex) ranges, for a compact human-readable overview.
function summarize_frame_labels(labels::Vector{String})
    ranges = Tuple{String, Int, Int}[]
    isempty(labels) && return ranges
    start = 1
    for i in 2:length(labels)
        if labels[i] != labels[i - 1]
            push!(ranges, (labels[i - 1], start, i - 1))
            start = i
        end
    end
    push!(ranges, (labels[end], start, length(labels)))
    return ranges
end

function expand_per_trigger_step(values)
    return repeat(values, inner=2)
end

# One measurement = two sequence steps: trigger HIGH (rising edge -> one MagSphere frame),
# then trigger LOW, with the coil currents held over both.
function build_coil_sequence_from_currents(scanner::MPIScanner,
                                          coilCurrents::Dict{Int, Vector{Float64}};
                                          measurementRate_Hz::Float64=TRIGGER_RATE_HZ)
    baseFreq = 125.0u"MHz"

    totalMeasurements = length(first(values(coilCurrents)))
    @assert all(length(currents) == totalMeasurements for currents in values(coilCurrents))
    maxCurrent = isempty(coilCurrents) ? 0.0 : maximum(maximum(abs.(currents)) for currents in values(coilCurrents))

    triggerVals = alternating_trigger_values(totalMeasurements)
    valuesPerCycle = length(triggerVals)
    stepTime_s = 1.0 / (2.0 * measurementRate_Hz)
    divider = round(Int, stepTime_s * ustrip(u"Hz", baseFreq) * valuesPerCycle)

    channels_trigger = TxChannel[
        StepwiseElectricalChannel(id="trigger", divider=divider, values=triggerVals, enable=Bool[])
    ]

    channels_cage1 = TxChannel[]
    for coil in LEFT_COIL_ORDER
        vals = expand_per_trigger_step(get(coilCurrents, coil, zeros(totalMeasurements)) .* u"A")
        push!(channels_cage1,
              StepwiseElectricalChannel(id="coil$(coil)", divider=divider, values=vals, enable=Bool[]))
    end

    # `coil1_fast` is the dedicated fast channel for the first coil in the left cage.
    periodicCoil1 = PeriodicElectricalChannel(
        id="coil1_fast",
        offset=0.0u"T",
        components=[PeriodicElectricalComponent(
            id="c1",
            divider=12480,
            amplitude=[0.0u"T"],
            phase=[0.0u"rad"],
            waveform="sine",
        )],
    )
    insert!(channels_cage1, 1, periodicCoil1)

    channels_cage2 = TxChannel[]
    for coil in RIGHT_COIL_ORDER
        vals = expand_per_trigger_step(get(coilCurrents, coil, zeros(totalMeasurements)) .* u"A")
        push!(channels_cage2,
              StepwiseElectricalChannel(id="coil$(coil)", divider=divider, values=vals, enable=Bool[]))
    end

    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage2 if ch isa StepwiseElectricalChannel)
    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage1 if ch isa StepwiseElectricalChannel)

    return Sequence(
        general=GeneralSettings(
            name="PorridgeMagSphereMeasurementPrimary",
            description="triggerRate=$(measurementRate_Hz)Hz, holdTime=$(HOLD_TIME_S)s, background=$(PRIMARY_BACKGROUND_MEASUREMENTS), pairsPerSide=$(PRIMARY_RANDOM_PAIRS_PER_SIDE), repeatsPerPair=$(PRIMARY_RANDOM_REPEATS_PER_PAIR), singleCoilFramesPerCoil=$(PRIMARY_SINGLE_COIL_FRAMES_PER_COIL), randomCycles=$(PRIMARY_RANDOM_CYCLES), maxCurrent=$(round(maxCurrent, digits=3)), periodicCheckIntervalFrames=$(PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES)",
            targetScanner=name(scanner),
            baseFrequency=baseFreq,
        ),
        fields=[
            MagneticField(id="Trigger", channels=channels_trigger,
                          safeStartInterval=0.0u"s", safeEndInterval=0.0u"s",
                          safeErrorInterval=0.0u"s", control=false, decouple=false),
            MagneticField(id="cage1", channels=channels_cage1,
                          safeStartInterval=0.0u"s", safeEndInterval=0.0u"s",
                          safeErrorInterval=0.0u"s", control=false, decouple=false),
            MagneticField(id="cage2", channels=channels_cage2,
                          safeStartInterval=0.0u"s", safeEndInterval=0.0u"s",
                          safeErrorInterval=0.0u"s", control=false, decouple=false),
        ],
        acquisition=AcquisitionSettings(
            channels=[RxChannel("rx1")],
            bandwidth=0.9765625u"MHz",
            numPeriodsPerFrame=1,
            numFrames=1,
            numAverages=1,
            numFrameAverages=1,
        ),
    )
end

# Missed-frame counts kept by PorridgeMagSphereMeasurementProtocol (from the sphere's timestamps).
function print_missed_frame_summary(protocol)
    println("MagSphere frames: $(protocol.receivedFrames) received, " *
            "$(protocol.missingFrames) missed during the run, " *
            "$(protocol.tailFillFrames) missing at the end (tail fill), " *
            "$(protocol.skippedFrames) skipped, $(protocol.irregularFrames) off the trigger grid")
    measured = MPIMeasurements.measuredMagSpherePeriod_s(protocol)
    println("Trigger period: expected $(round(protocol.triggerPeriod_us / 1000, digits=3)) ms, " *
            "measured $(round(measured * 1000, digits=4)) ms")
    lost = protocol.missingFrames + protocol.tailFillFrames
    if lost > 0
        println("⚠ $lost of $(protocol.totalFrames) frames are NaN placeholders for missed frames (/frames/missing in the HDF5 file)")
    end
end

# 1. Initialize
scanner = MPIScanner("PorridgeMagSphere", robust=true)
protocol = Protocol("PorridgeMagSphereMeasurement", scanner)
# Primary staged protocol (durations at 100 Hz, every coil configuration held 1 s):
#   1) 40 s background
#   2) single-coil max-current checks, 1 s per coil (18 s)
#   3) 10x { 1000 right-side draws x 1 s, 1000 left-side draws x 1 s,
#            40 s background (separator only, not a calibration bracket) }
#   4) 40 s background
#   5) 1000 all-18-coils draws x 1 s -- the "double-sided"/simultaneous block;
#      deliberately LAST among the data-collection segments
#   6) 40 s background
#   7) final single-coil max-current checks
# Additionally, a single-coil check is spliced in every ~33 min throughout the whole run
# (steps 3-6 above), so a coil that fails mid-run doesn't silently invalidate everything after it.
primaryCurrents = build_primary_coil_currents()
totalFrames = length(first(values(primaryCurrents)))
println("Primary run: $totalFrames frames at $(TRIGGER_RATE_HZ) Hz, " *
        "≈ $(round(totalFrames / TRIGGER_RATE_HZ / 3600, digits=2)) h")
protocol.params.sequence = build_coil_sequence_from_currents(
    scanner,
    primaryCurrents;
    measurementRate_Hz=TRIGGER_RATE_HZ,
)
init(protocol)

# 2. Execute
println("Starting measurement...")
biChannel = execute(protocol, 3)

# 3. Wait for completion. Ctrl+C stops the measurement and still saves what was collected.
stopping = false
try
  while true
    try
      sleep(stopping ? 0.1 : 2.0)

      # A failed protocol closes the channel; its last event (the error) can still be taken.
      try
          put!(biChannel, ProgressQueryEvent())
      catch e
          isa(e, InvalidStateException) || rethrow(e)
      end
      if !isready(biChannel) && !isopen(biChannel)
          println("The protocol ended without a result; see the log above.")
          break
      end

      if isready(biChannel)
          event = take!(biChannel)

          if isa(event, ProgressEvent)
              pct = round(event.done / event.total * 100, digits=1)
              println("Progress: $pct% ($(event.done)/$(event.total)), missed frames: $(protocol.missingFrames)")

          elseif isa(event, FinishedNotificationEvent)
              println("Measurement complete!")
              print_missed_frame_summary(protocol)

              # Save to configured datasetStore location
              storePath = scanner.generalParams.datasetStore
              mkpath(expanduser(storePath))  # Ensure directory exists
              filename = joinpath(expanduser(storePath), "measurement_$(Dates.format(now(), "yyyymmdd_HHMMSS"))_magsphere.h5")
              put!(biChannel, FileStorageRequestEvent(filename))

              # Wait for save confirmation (drain any stale ProgressEvents)
              saveEvent = nothing
              while true
                  saveEvent = take!(biChannel)
                  isa(saveEvent, ProgressEvent) || break
              end
              if isa(saveEvent, StorageSuccessEvent)
                  println("Saved to: $filename")
              elseif isa(saveEvent, ExceptionEvent)
                  println("Save error: $(saveEvent.exception)")
              else
                  println("⚠ Unexpected event: $(typeof(saveEvent))")
              end

              # Acknowledge
              put!(biChannel, FinishedAckEvent())
              break

          elseif isa(event, ExceptionEvent)
              println("Error: $(event.exception)")
              break

          elseif isa(event, IllegaleStateEvent)
              println("Error: $(event.message)")
              break
          end
      end
    catch e
      if isa(e, InterruptException) && !stopping
          println("\nStopping measurement, saving collected data...")
          global stopping = true
          put!(biChannel, StopEvent())
      else
          rethrow(e)
      end
    end
  end
catch e
  if isa(e, InterruptException)
    println("\nInterrupt received; attempting graceful shutdown...")
  else
    rethrow(e)
  end
end

# 4. Cleanup
cleanup(protocol)
close(scanner)

println("\nDone!")
