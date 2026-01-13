"""
Full-Featured Porridge Field Measurement Example

This demonstrates advanced features:
- Custom measurement parameters
- Progress monitoring
- Automatic saving with custom naming
- Error handling
"""

using MPIMeasurements
using Dates

println("="^80)
println("Porridge Field Measurement - Full Example")
println("="^80)
println("Time: $(now())")
println()

# Configuration
const NUM_MEASUREMENTS = 20  # Measurements per field point
const STABILIZATION_TIME = 0.5  # seconds
const SEQUENCE_NAME = "TwoCoilTest"  # or your custom sequence

# 1. Initialize scanner
println("🔧 Initializing scanner...")
scanner = MPIScanner("PorridgeFieldCamera", robust=true)
println("  ✓ Scanner initialized: $(scanner.name)")

# 2. Initialize protocol
println("🔧 Initializing protocol...")
protocol = Protocol("PorridgeFieldMeasurement", scanner)
println("  ✓ Protocol: $(description(protocol))")
println("  ✓ Sequence: $(protocol.params.sequence.general.name)")
println("  ✓ Estimated time: $(timeEstimate(protocol))")

# Initialize protocol
init(protocol)
println()

# 3. Execute measurement
println("🚀 Starting measurement...")
println("  - Measurements per point: $NUM_MEASUREMENTS")
println("  - Stabilization time: $(STABILIZATION_TIME)s")
println()

biChannel = execute(protocol, 3)

# 4. Monitor progress
startTime = now()
lastProgress = 0

while true
    sleep(2.0)
    
    # Query progress
    put!(biChannel, ProgressQueryEvent())
    
    if isready(biChannel)
        event = take!(biChannel)
        
        if isa(event, ProgressEvent)
            pct = round(event.done / event.total * 100, digits=1)
            
            # Only print if progress changed
            if pct != lastProgress
                elapsed = Dates.value(now() - startTime) / 1000  # seconds
                remaining = event.total > event.done ? elapsed * (event.total - event.done) / event.done : 0
                
                println("📊 Progress: $pct% ($(event.done)/$(event.total)) | " *
                       "Elapsed: $(round(elapsed, digits=1))s | " *
                       "Remaining: ~$(round(remaining, digits=1))s")
                lastProgress = pct
            end
            
        elseif isa(event, FinishedNotificationEvent)
            println()
            println("✅ Measurement complete!")
            
            # Generate filename with timestamp
            storePath = scanner.generalParams.datasetStore
            mkpath(expanduser(storePath))
            timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
            filename = joinpath(expanduser(storePath), 
                              "field_measurement_$(SEQUENCE_NAME)_$timestamp.h5")
            
            # Request save
            println("💾 Saving to: $filename")
            put!(biChannel, FileStorageRequestEvent(filename))
            
            # Wait for save confirmation
            saveEvent = take!(biChannel)
            if isa(saveEvent, StorageSuccessEvent)
                println("✅ Data saved successfully")
                
                # Print file info
                using HDF5
                h5open(filename, "r") do f
                    println("\n📊 Saved datasets:")
                    for key in sort(collect(keys(f)))
                        data = read(f, key)
                        if ndims(data) > 0
                            println("  - $key: $(size(data))")
                        else
                            println("  - $key: $data")
                        end
                    end
                end
                
            elseif isa(saveEvent, ExceptionEvent)
                println("❌ Save error: $(saveEvent.exception)")
                @error "Failed to save" exception=saveEvent.exception
            end
            
            # Give async operations time to complete
            sleep(2.0)
            
            # Acknowledge completion
            put!(biChannel, FinishedAckEvent())
            break
            
        elseif isa(event, ExceptionEvent)
            println("❌ Error during measurement: $(event.exception)")
            @error "Measurement failed" exception=event.exception
            break
        end
    end
end

# 5. Cleanup
println("\n🧹 Cleaning up...")
cleanup(protocol)
close(scanner)

totalTime = Dates.value(now() - startTime) / 1000
println("✅ Done! Total time: $(round(totalTime, digits=1))s")
println("="^80)
