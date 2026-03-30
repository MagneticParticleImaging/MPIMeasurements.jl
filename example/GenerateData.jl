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

function line_currents_coil12_coil15(numMeasurements::Int;
                                     maxCurrent_A::Float64=0.95,
                                     sortByCurrentJumps::Bool=false)
    x_line = sortByCurrentJumps ?
        collect(range(-0.04, 0.04; length=numMeasurements)) :
        vcat(collect(range(-0.04, 0.04; length=fld(numMeasurements, 2))),
             collect(range(0.04, -0.04; length=numMeasurements - fld(numMeasurements, 2))))

    total = zeros(Float64, numMeasurements)
    if sortByCurrentJumps
        for i in 2:numMeasurements
            total[i] = clamp(total[i-1] + 0.06 * randn(), -1.0, 1.0)
        end
        total .*= maxCurrent_A
    else
        total .= (2 .* rand(numMeasurements) .- 1) .* maxCurrent_A
    end

    alpha = (x_line .+ 0.04) ./ 0.08
    i12 = (1 .- alpha) .* total
    i15 = alpha .* total

    return i12 .* u"A", i15 .* u"A"
end

function expand_per_trigger_step(values)
    return repeat(values, inner=2)
end

function build_random_line_sequence(scanner::MPIScanner;
                                    numMeasurements::Int=10_000,
                                    sortedCurrentPath::Bool=false,
                                    measurementRate_Hz::Float64=10.0)
    baseFreq = 125.0u"MHz"

    triggerVals = alternating_trigger_values(numMeasurements)
    coil12PerMeas, coil15PerMeas = line_currents_coil12_coil15(
        numMeasurements;
        sortByCurrentJumps=sortedCurrentPath,
    )
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
            name="RandomLine10k",
            description="10k triggered measurements on x-line with random coil12/15 currents",
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
if false
    protocol.params.sequence = build_random_line_sequence(
        scanner;
        numMeasurements=100,
        sortedCurrentPath=true,
        measurementRate_Hz=50.0,
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
