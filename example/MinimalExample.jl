"""
Minimal Working Example: Porridge Field Measurement

This is the absolute minimal code to run a field measurement.
For more features, see PorridgeFieldMeasurementExample.jl
"""

using MPIMeasurements
using Dates

println("Starting Porridge field measurement...")
println("Time: $(now())")

# 1. Initialize
scanner = MPIScanner("PorridgeFieldCamera", robust=true)
protocol = Protocol("PorridgeFieldMeasurement", scanner)
init(protocol)

# 2. Execute
println("\nStarting measurement...")
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
            println("\n✓ Measurement complete!")
            
            # Save
            filename = "measurement_$(Dates.format(now(), "yyyymmdd_HHMMSS")).h5"
            put!(biChannel, FileStorageRequestEvent(filename))
            
            # Wait for save confirmation
            saveEvent = take!(biChannel)
            if isa(saveEvent, StorageSuccessEvent)
                println("✓ Saved to: $filename")
            end
            
            # Acknowledge
            put!(biChannel, FinishedAckEvent())
            break
            
        elseif isa(event, ExceptionEvent)
            println("✗ Error: $(event.exception)")
            break
        end
    end
end

# 4. Cleanup
cleanup(protocol)
close(scanner)

println("\nDone!")
