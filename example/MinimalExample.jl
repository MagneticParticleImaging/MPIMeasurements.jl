# Minimal example: Porridge field measurement

using MPIMeasurements
using Dates

println("Starting Porridge field measurement...")

# 1. Initialize
scanner = MPIScanner("PorridgeFieldCamera", robust=true)
protocol = Protocol("PorridgeFieldMeasurement", scanner)
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
