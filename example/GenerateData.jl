# Minimal example: Porridge field measurement

using MPIMeasurements
using Dates
using Random
using Unitful

println("Starting Porridge field measurement...")

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
    else
        throw(ArgumentError("Unknown mode=$mode. Use :random_independent or :nested_grid_random_outer"))
    end
end

function expand_pairs_to_measurements(i12Pairs::Vector{Float64}, i15Pairs::Vector{Float64}; repeatsPerPair::Int=10)
    i12 = repeat(i12Pairs, inner=repeatsPerPair)
    i15 = repeat(i15Pairs, inner=repeatsPerPair)
    return i12, i15
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

function build_coil_pair_sequence(scanner::MPIScanner;
                                  mode::Symbol=:random_independent,
                                  numCurrentPairs::Int=1_000,
                                  repeatsPerPair::Int=10,
                                  backgroundMeasurements::Int=50,
                                  maxCurrent_A::Float64=0.95,
                                  measurementRate_Hz::Float64=10.0)
    baseFreq = 125.0u"MHz"

    i12Pairs, i15Pairs = build_current_pairs(mode, numCurrentPairs; maxCurrent_A)
    i12Meas, i15Meas = expand_pairs_to_measurements(i12Pairs, i15Pairs; repeatsPerPair)
    i12All, i15All = add_background_measurements(i12Meas, i15Meas; backgroundMeasurements)

    totalMeasurements = length(i12All)
    triggerVals = alternating_trigger_values(totalMeasurements)

    coil12PerMeas = i12All .* u"A"
    coil15PerMeas = i15All .* u"A"
    coil12Vals = expand_per_trigger_step(coil12PerMeas)
    coil15Vals = expand_per_trigger_step(coil15PerMeas)

    valuesPerCycle = length(triggerVals)
    stepTime_s = 1.0 / (2.0 * measurementRate_Hz)
    divider = round(Int, stepTime_s * ustrip(u"Hz", baseFreq) * valuesPerCycle)

    channels_trigger = TxChannel[
        StepwiseElectricalChannel(id="trigger", divider=divider, values=triggerVals, enable=Bool[])
    ]

    channels_cage2 = TxChannel[]
    for coil in 10:18
        coilID = "coil$(coil)"
        vals = if coil == 12
            coil12Vals
        elseif coil == 15
            coil15Vals
        else
            zeros(length(triggerVals)) .* u"A"
        end
        push!(channels_cage2,
              StepwiseElectricalChannel(id=coilID, divider=divider, values=vals, enable=Bool[]))
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
        push!(channels_cage1,
              StepwiseElectricalChannel(
                  id="coil$(coil)",
                  divider=divider,
                  values=zeros(length(triggerVals)) .* u"A",
                  enable=Bool[],
              ))
    end

    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage2 if ch isa StepwiseElectricalChannel)
    @assert all(length(ch.values) == length(triggerVals) for ch in channels_cage1 if ch isa StepwiseElectricalChannel)

    return Sequence(
        general=GeneralSettings(
            name="CoilPairSequence",
            description="mode=$(mode), pairs=$(numCurrentPairs), repeats=$(repeatsPerPair), bg=$(backgroundMeasurements)",
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
    protocol.params.sequence = build_coil_pair_sequence(
        scanner;
        mode=:random_independent,
        numCurrentPairs=1_000,
        repeatsPerPair=10,
        backgroundMeasurements=50,
        measurementRate_Hz=20.0,
    )
end
init(protocol)

# 2. Execute
println("Starting measurement...")
biChannel = execute(protocol, 3)

# 3. Wait for completion
while true
    sleep(2.0)
    
    # Check status
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
end

# 4. Cleanup
cleanup(protocol)
close(scanner)

println("\nDone!")
