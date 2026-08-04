# Minimal example: Porridge field measurement

using MPIMeasurements
using Dates
using Random
using Unitful

# Make a single Ctrl+C throw InterruptException so the running measurement
# can be stopped cleanly and the partial data can still be saved.
Base.exit_on_sigint(false)

println("Starting Porridge field measurement...")

const RIGHT_COIL_ORDER = [17, 3, 18, 14, 12, 16, 10, 11, 13]
const LEFT_COIL_ORDER = [9, 6, 8, 7, 15, 5, 4, 2, 1]

const PRIMARY_BACKGROUND_MEASUREMENTS = 1_000
const PRIMARY_RANDOM_PAIRS_PER_SIDE = 1_000
const PRIMARY_RANDOM_CYCLES = 10 # number of times the "1000 pairs/side, 50 reps/pair" R+L block is repeated. 1 = single pass (right block once, left block once), as intended.
const PRIMARY_RANDOM_MAX_CURRENT_A = 0.95
const PRIMARY_SINGLE_COIL_MAX_CURRENT_A = 0.95
const PRIMARY_RANDOM_REPEATS_PER_PAIR = 50
# A single-coil check only brackets the run at start/end, so a coil that fails partway
# through leaves everything after it untrustworthy with no way to tell where the failure
# happened. Re-running the 18-frame check every ~50,000 frames (~17 min at 50 Hz) bounds
# that uncertainty window instead of covering the whole run. Set to 0 to disable.
const PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES = 50_000

# --- FFP circle trajectory (from magneticFieldEstimation work_circle6.jl) ----
# 360 optimized current sets (one per degree) that move the FFP on a circle in
# the yz plane, radius 0.02 m, centered at the origin. CSV columns I1..I6 are
# the 6 inputs of model6.bson (= 2026_07_07_initial_model.pt), one row per
# degree (see the "degree,I1,I2,I3,I4,I5,I6" header in the file).
#
# ⚠ The mapping from CSV column to physical coil id below is NOT verified — it
# depends on the column order of the model's training data. Candidates:
#   ascending coil ids:            [2, 3, 6, 11, 12, 15]
#   middle-coils definition order: [3, 12, 11, 6, 15, 2]  (right 3,12,11, then left 6,15,2)
# Hint for resolving it: model input 3 is nearly dead (field response ~1000x
# weaker than the other inputs). This trajectory confirms it again: column I3
# stays well below 0.55 A over the whole circle while every other column
# swings up to several amps. If one middle coil was broken or disconnected
# during the training measurements, that coil is column 3.
#
# ⚠ This trajectory's peak current is ~9.52 A (close to the Imax=10 A used
# during optimization) — far higher than the 0.95 A random-mode trainings and
# the earlier R=0.045 circle. Confirm the amplifiers can sustain that before
# running on hardware; maxCurrent_A must be raised to at least that value.
const CIRCLE6_CSV_FILE = joinpath(@__DIR__, "circle6_R-0.02_T-360_Imax-10.0_dImax-5.0_B-0.0001_g-0.003_currents.csv")
const CIRCLE6_COIL_ORDER = [2, 3, 6, 11, 12, 15]

function read_circle6_csv(csvPath::AbstractString)
    lines = readlines(csvPath)
    isempty(lines) && throw(ArgumentError("Empty CSV file: $csvPath"))
    header = split(lines[1], ",")
    strip(header[1]) == "degree" ||
        throw(ArgumentError("Unexpected CSV header in $csvPath: $(lines[1])"))
    nCoilsInFile = length(header) - 1
    trajectory = Vector{Vector{Float64}}()
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ",")
        push!(trajectory, parse.(Float64, fields[2:end]))
    end
    isempty(trajectory) && throw(ArgumentError("No current rows found in $csvPath"))
    all(p -> length(p) == nCoilsInFile, trajectory) ||
        throw(ArgumentError("Inconsistent current counts in $csvPath"))
    return trajectory
end

function circle6_trajectory_coils(numLoops::Int; maxCurrent_A::Float64=0.95,
                                  csvPath::AbstractString=CIRCLE6_CSV_FILE)
    trajectory = read_circle6_csv(csvPath)
    length(first(trajectory)) == length(CIRCLE6_COIL_ORDER) ||
        throw(ArgumentError("CSV has $(length(first(trajectory))) coils, expected $(length(CIRCLE6_COIL_ORDER))"))
    peak = maximum(p -> maximum(abs, p), trajectory)
    peak <= maxCurrent_A ||
        throw(ArgumentError("Trajectory peak current $(round(peak, digits=4)) A exceeds maxCurrent_A = $(maxCurrent_A) A; pass a larger maxCurrent_A only if the amplifiers allow it"))
    coilCurrents = Dict{Int, Vector{Float64}}()
    for (col, coilID) in enumerate(CIRCLE6_COIL_ORDER)
        coilCurrents[coilID] = repeat([p[col] for p in trajectory], outer=numLoops)
    end
    return coilCurrents
end

function alternating_trigger_values(numMeasurements::Int)
    vals = zeros(Float64, 2 * numMeasurements)
    vals[1:2:end] .= 0.9
    return vals .* u"A"
end

function random_independent_pairs(numPairs::Int; maxCurrent_A::Float64=0.95)
    i12 = (2 .* rand(numPairs) .- 1) .* maxCurrent_A
    i15 = (2 .* rand(numPairs) .- 1) .* maxCurrent_A
    return i12, i15
end

function random_independent_right_coils(numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    return random_independent_coils(RIGHT_COIL_ORDER, numPairs; maxCurrent_A, repeatsPerPair)
end

function random_independent_left_coils(numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    return random_independent_coils(LEFT_COIL_ORDER, numPairs; maxCurrent_A, repeatsPerPair)
end

function random_independent_middle_coils(numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    return random_independent_coils([RIGHT_COIL_ORDER[2], RIGHT_COIL_ORDER[5], RIGHT_COIL_ORDER[8], LEFT_COIL_ORDER[2], LEFT_COIL_ORDER[5], LEFT_COIL_ORDER[8]], numPairs; maxCurrent_A, repeatsPerPair)
end

function random_independent_coils(coilIDs::AbstractVector{Int}, numPairs::Int; maxCurrent_A::Float64=0.95, repeatsPerPair::Int=1)
    repeatsPerPair >= 1 || throw(ArgumentError("repeatsPerPair must be >= 1"))
    coilCurrents = Dict{Int, Vector{Float64}}()
    for coilID in coilIDs
        baseValues = (2 .* rand(numPairs) .- 1) .* maxCurrent_A
        coilCurrents[coilID] = repeat(baseValues, inner=repeatsPerPair)
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

function single_coil_check_segment(; maxCurrent_A::Float64=PRIMARY_SINGLE_COIL_MAX_CURRENT_A)
    segment = all_coils_zero_currents(18)
    for coilID in 1:18
        segment[coilID][coilID] = maxCurrent_A
    end
    return segment
end

# Insert an 18-frame single-coil check every `intervalFrames` frames throughout an
# already-built sequence, so a coil that fails mid-run is caught within one interval
# instead of only at the start/end checks. Checkpoints are computed against the
# pre-insertion frame count and applied back-to-front so earlier insertions don't shift
# the position of checkpoints still to be processed. The last `intervalFrames ÷ 4` frames
# are left alone since the run's own final check segment already covers that region.
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
                                      periodicCheckInterval_frames::Int=PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES)
    total = all_coils_zero_currents(0)

    # Initial background.
    append_currents_segment!(total, all_coils_zero_currents(backgroundMeasurements))

    # Quick per-coil amplifier checks.
    append_currents_segment!(total, single_coil_check_segment(; maxCurrent_A=singleCoilMaxCurrent_A))

    # Right-side block, then left-side block: randomPairsPerSide base pairs, each held for
    # repeatsPerPair consecutive measurements before moving to the next pair. With the default
    # randomCycles=1 this runs exactly once per side (1000 pairs x 50 repeats = 50,000 frames/side).
    for _ in 1:randomCycles
        append_currents_segment!(total, random_independent_right_coils(randomPairsPerSide; maxCurrent_A, repeatsPerPair))
        append_currents_segment!(total, random_independent_left_coils(randomPairsPerSide; maxCurrent_A, repeatsPerPair))
    end

    # Middle background before the combined 18-coil random block.
    append_currents_segment!(total, all_coils_zero_currents(backgroundMeasurements))

    # All 18 coils randomly driven together.
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

function nested_grid_random_outer_pairs(numPairs::Int;
                                        maxCurrent_A::Float64=0.95,
                                        innerSteps::Int=100,
                                        outerSteps::Int=100)
    innerVals = collect(range(-maxCurrent_A, maxCurrent_A; length=innerSteps))
    outerVals = collect(range(-maxCurrent_A, maxCurrent_A; length=outerSteps))
    outerOrder = randperm(outerSteps)

    i12 = Float64[]
    i15 = Float64[]
    sizehint!(i12, numPairs)
    sizehint!(i15, numPairs)

    for outerIdx in outerOrder
        outerCurrent = outerVals[outerIdx]
        for innerCurrent in innerVals
            push!(i12, innerCurrent)
            push!(i15, outerCurrent)
            if length(i12) == numPairs
                return i12, i15
            end
        end
    end

    throw(ArgumentError("Requested $numPairs pairs exceeds available nested-grid samples $(innerSteps * outerSteps)"))
end

function build_current_pairs(mode::Symbol, numPairs::Int; maxCurrent_A::Float64=0.95)
    if mode == :random_independent
        return random_independent_pairs(numPairs; maxCurrent_A)
    elseif mode == :nested_grid_random_outer
        return nested_grid_random_outer_pairs(numPairs; maxCurrent_A, innerSteps=100, outerSteps=100)
    elseif mode == :random_independent_right_coils
        return random_independent_right_coils(numPairs; maxCurrent_A)
    elseif mode == :random_independent_left_coils
        return random_independent_left_coils(numPairs; maxCurrent_A)
    elseif mode == :random_independent_middle_coils
        return random_independent_middle_coils(numPairs; maxCurrent_A)
    elseif mode == :circle6_yz
        # numPairs is reinterpreted as the number of revolutions around the 360-point circle (use numCurrentPairs=1 for a single loop).
        return circle6_trajectory_coils(numPairs; maxCurrent_A)
    else
        throw(ArgumentError("Unknown mode=$mode. Use :random_independent, :nested_grid_random_outer, :random_independent_right_coils, :random_independent_left_coils, :random_independent_middle_coils, or :circle6_yz"))
    end
end

function expand_pairs_to_measurements(i12Pairs::Vector{Float64}, i15Pairs::Vector{Float64}; repeatsPerPair::Int=50)
    i12 = repeat(i12Pairs, inner=repeatsPerPair)
    i15 = repeat(i15Pairs, inner=repeatsPerPair)
    return i12, i15
end

function expand_pairs_to_measurements(coilCurrents::Dict{Int, Vector{Float64}}; repeatsPerPair::Int=50)
    expandedCurrents = Dict{Int, Vector{Float64}}()
    for (coilID, currents) in coilCurrents
        expandedCurrents[coilID] = repeat(currents, inner=repeatsPerPair)
    end
    return expandedCurrents
end

function add_background_measurements(coilCurrents::Dict{Int, Vector{Float64}}; backgroundMeasurements::Int=50)
    bg = zeros(Float64, backgroundMeasurements)
    coilCurrentsAll = Dict{Int, Vector{Float64}}()
    for (coilID, currents) in coilCurrents
        coilCurrentsAll[coilID] = vcat(bg, currents, bg)
    end
    return coilCurrentsAll
end

function add_background_measurements(i12::Vector{Float64}, i15::Vector{Float64}; backgroundMeasurements::Int=50)
    bg = zeros(Float64, backgroundMeasurements)
    i12All = vcat(bg, i12, bg)
    i15All = vcat(bg, i15, bg)
    return i12All, i15All
end

function expand_per_trigger_step(values)
    return repeat(values, inner=2)
end

function build_coil_sequence_from_currents(scanner::MPIScanner,
                                          coilCurrents::Dict{Int, Vector{Float64}};
                                          measurementRate_Hz::Float64=10.0)
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
            name="PorridgeFieldMeasurementPrimary",
            description="background=$(PRIMARY_BACKGROUND_MEASUREMENTS), pairsPerSide=$(PRIMARY_RANDOM_PAIRS_PER_SIDE), repeatsPerPair=$(PRIMARY_RANDOM_REPEATS_PER_PAIR), randomCycles=$(PRIMARY_RANDOM_CYCLES), maxCurrent=$(round(maxCurrent, digits=3)), periodicCheckIntervalFrames=$(PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES)",
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

function build_coil_pair_sequence(scanner::MPIScanner;
                                  mode::Symbol=:random_independent,
                                  numCurrentPairs::Int=1_000,
                                  repeatsPerPair::Int=50,
                                  backgroundMeasurements::Int=50,
                                  maxCurrent_A::Float64=0.95,
                                  measurementRate_Hz::Float64=10.0)
    baseFreq = 125.0u"MHz"

    currentPairs = build_current_pairs(mode, numCurrentPairs; maxCurrent_A)
    isCoilDictMode = currentPairs isa Dict

    if isCoilDictMode
        coilCurrentsMeas = expand_pairs_to_measurements(currentPairs; repeatsPerPair)
        coilCurrentsAll = add_background_measurements(coilCurrentsMeas; backgroundMeasurements)
        totalMeasurements = length(first(values(coilCurrentsAll)))
    else
        i12Pairs, i15Pairs = currentPairs
        i12Meas, i15Meas = expand_pairs_to_measurements(i12Pairs, i15Pairs; repeatsPerPair)
        i12All, i15All = add_background_measurements(i12Meas, i15Meas; backgroundMeasurements)
        totalMeasurements = length(i12All)
    end
    
    triggerVals = alternating_trigger_values(totalMeasurements)

    if !isCoilDictMode
        coil12PerMeas = i12All .* u"A"
        coil15PerMeas = i15All .* u"A"
        coil12Vals = expand_per_trigger_step(coil12PerMeas)
        coil15Vals = expand_per_trigger_step(coil15PerMeas)
    end

    valuesPerCycle = length(triggerVals)
    stepTime_s = 1.0 / (2.0 * measurementRate_Hz)
    divider = round(Int, stepTime_s * ustrip(u"Hz", baseFreq) * valuesPerCycle)

    channels_trigger = TxChannel[
        StepwiseElectricalChannel(id="trigger", divider=divider, values=triggerVals, enable=Bool[])
    ]

    channels_cage2 = TxChannel[]
    for coil in 10:18
        vals = if isCoilDictMode && haskey(coilCurrentsAll, coil)
            expand_per_trigger_step(coilCurrentsAll[coil] .* u"A")
        elseif coil == 12 && !isCoilDictMode
            coil12Vals
        elseif coil == 15 && !isCoilDictMode
            coil15Vals
        else
            zeros(length(triggerVals)) .* u"A"
        end
        push!(channels_cage2,
              StepwiseElectricalChannel(id="coil$(coil)", divider=divider, values=vals, enable=Bool[]))
    end

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

    channels_cage1 = TxChannel[periodicCoil1]
    for coil in 1:9
        vals = if isCoilDictMode && haskey(coilCurrentsAll, coil)
            expand_per_trigger_step(coilCurrentsAll[coil] .* u"A")
        else
            zeros(length(triggerVals)) .* u"A"
        end
        push!(channels_cage1,
              StepwiseElectricalChannel(
                  id="coil$(coil)",
                  divider=divider,
                  values=vals,
                  enable=Bool[],
              ))
    end

    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage2 if ch isa StepwiseElectricalChannel)
    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage1 if ch isa StepwiseElectricalChannel)

    return Sequence(
        general=GeneralSettings(
            name="CoilPairSequence",
            description="mode=$(mode), pairs=$(numCurrentPairs), repeats=$(repeatsPerPair), bg=$(backgroundMeasurements), right=$(RIGHT_COIL_ORDER), left=$(LEFT_COIL_ORDER)" *
                        (mode == :circle6_yz ? ", circle6order=$(CIRCLE6_COIL_ORDER)" : ""),
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

# 1. Initialize
scanner = MPIScanner("PorridgeFieldCamera", robust=true)
protocol = Protocol("PorridgeFieldMeasurement", scanner)
if true
    # Primary staged protocol:
    #   1) 1000 background frames
    #   2) 18 one-frame single-coil max-current checks
    #   3) 1000 right-side pairs x 50 repeats (50,000 frames), then
    #      1000 left-side pairs x 50 repeats (50,000 frames)
    #   4) 1000 background frames
    #   5) 1000 all-18-coils pairs x 50 repeats (50,000 frames)
    #   6) 1000 background frames
    #   7) 18 final one-frame single-coil max-current checks
    # Additionally, an 18-frame single-coil check is spliced in every
    # PRIMARY_PERIODIC_CHECK_INTERVAL_FRAMES frames throughout the whole run (steps 3-6
    # above), so a coil that fails mid-run doesn't silently invalidate everything after it.
    primaryCurrents = build_primary_coil_currents()
    protocol.params.sequence = build_coil_sequence_from_currents(
        scanner,
        primaryCurrents;
        measurementRate_Hz=50.0,
    )
elseif false
    # FFP circle in the yz plane (r = 0.02 m), currents from CIRCLE6_CSV_FILE.
    # This remains available for later use, but is not the primary run mode.
    protocol.params.sequence = build_coil_pair_sequence(
        scanner;
        mode=:circle6_yz,
        numCurrentPairs=1,
        repeatsPerPair=50,
        backgroundMeasurements=50,
        maxCurrent_A=9.6,
        measurementRate_Hz=50.0,
    )
end
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

      put!(biChannel, ProgressQueryEvent())

      if isready(biChannel)
          event = take!(biChannel)

          if isa(event, ProgressEvent)
              pct = round(event.done / event.total * 100, digits=1)
              println("Progress: $pct% ($(event.done)/$(event.total))")

          elseif isa(event, FinishedNotificationEvent)
              println("Measurement complete!")
              
              # Save to configured datasetStore location
              storePath = scanner.generalParams.datasetStore
              mkpath(expanduser(storePath))  # Ensure directory exists
              filename = joinpath(expanduser(storePath), "measurement_$(Dates.format(now(), "yyyymmdd_HHMMSS")).h5")
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
          end
      end
    catch e
      if isa(e, InterruptException) && !stopping
          println("\nStopping measurement, saving collected data...")
          stopping = true
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
