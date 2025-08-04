export PNSTestProtocol, PNSTestProtocolParams
using Dates
"""
Parameters for the PNSTestProtocol
"""
Base.@kwdef mutable struct PNSTestProtocolParams <: ProtocolParams
  "Strings to print"
  testMeasurements::Vector{String} = ["Measurement1", "Measurement2", "Measurement3", "Measurement4", "Measurement5"]
  "Minimum wait time between measurements (seconds)"
  minWaitTime::Float64 = 1.0
  "Maximum wait time between measurements (seconds)"
  maxWaitTime::Float64 = 3.0
end
function PNSTestProtocolParams(dict::Dict, scanner::MPIScanner)
  params = params_from_dict(PNSTestProtocolParams, dict)
  return params
end
PNSTestProtocolParams(dict::Dict) = params_from_dict(PNSTestProtocolParams, dict)

Base.@kwdef mutable struct PNSTestProtocol <: Protocol
  @add_protocol_fields PNSTestProtocolParams

  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  stopped::Bool = false
  restored::Bool = false
  measuring::Bool = false
  currStep::Int = 0
  currentMeasurement::String = ""
  waitingForDecision::Bool = false
end

function requiredDevices(protocol::PNSTestProtocol)
  result = []
  return result
end

function _init(protocol::PNSTestProtocol)
  if isnothing(protocol.params.testMeasurements)
    throw(IllegalStateException("Protocol requires test measurements"))
  end

  return nothing
end

function timeEstimate(protocol::PNSTestProtocol)
  numMeasurements = length(protocol.params.testMeasurements)
  avgWaitTime = (protocol.params.minWaitTime + protocol.params.maxWaitTime) / 2
  totalTime = numMeasurements * avgWaitTime
  est = "≈ $(round(totalTime, digits=1)) seconds"
  return est
end

function enterExecute(protocol::PNSTestProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.measuring = true
end


function _execute(protocol::PNSTestProtocol)
  @debug "Measurement protocol started"

  protocol.currStep = 0
  index = 1
  
  while index <= length(protocol.params.testMeasurements)
    # Handle pause/resume logic
    notifiedStop = false
    while protocol.stopped
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
      if !notifiedStop
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
    
    # Check if we should cancel
    if protocol.cancelled
      break
    end
    
    protocol.currStep = index
    testMeasurement = protocol.params.testMeasurements[index]
    protocol.currentMeasurement = testMeasurement
    
    @info "Test measurement: $testMeasurement"
    
    # Random wait time between min and max
    waitTime = protocol.params.minWaitTime + rand() * (protocol.params.maxWaitTime - protocol.params.minWaitTime)
    
    # Sleep with cancellation checks
    sleepStart = time()
    while time() - sleepStart < waitTime
      if protocol.stopped || protocol.cancelled
        break
      end
      sleep(0.1)
    end
    
    # Check again after sleep if we should stop or cancel
    if protocol.stopped || protocol.cancelled
      continue  # Go back to pause/cancel handling
    end
    
    # Ask for decision after each measurement (except the last one)
    if index < length(protocol.params.testMeasurements)
      protocol.waitingForDecision = true
      decision = askChoices(protocol, "Measurement '$testMeasurement' completed. How should we proceed?", 
                           ["Continue", "Repeat", "Cancel"])
      protocol.waitingForDecision = false
      
      if decision == 3  # "Cancel" 
        @info "Protocol cancelled by user decision."
        protocol.cancelled = true
        break
      elseif decision == 2  # "Repeat"
        @info "Repeating measurement: $testMeasurement"
        # Don't increment index, so we repeat the current measurement
        continue
      else  # decision == 1, "Continue"
        @info "Continuing to next measurement."
      end
    end
    
    # Move to next measurement
    index += 1
  end

  if !protocol.cancelled
    protocol.done = true
    @info "Protocol finished successfully."
  else
    @info "Protocol was cancelled."
  end
  
  # Always send FinishedNotificationEvent, even if cancelled
  put!(protocol.biChannel, FinishedNotificationEvent())
  
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end
  
  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function cleanup(protocol::PNSTestProtocol)

end

function stop(protocol::PNSTestProtocol)
    protocol.stopped = true
    protocol.restored = false
    protocol.measuring = false
    @info "Protocol paused."
end

function resume(protocol::PNSTestProtocol)
  protocol.stopped = false
  protocol.restored = true
  protocol.measuring = true
  @info "Protocol resumed."
end

function cancel(protocol::PNSTestProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end

function handleEvent(protocol::PNSTestProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel, ProgressEvent(protocol.currStep, length(protocol.params.testMeasurements), "Step", event))
end

function handleEvent(protocol::PNSTestProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURR"
    data = protocol.currentMeasurement
  elseif event.message == "STEP"
    data = protocol.currStep
  elseif event.message == "TOTAL"
    data = length(protocol.params.testMeasurements)
  elseif event.message == "STATUS"
    if protocol.waitingForDecision
      data = "Waiting for decision"
    elseif protocol.measuring
      data = "Measuring"
    elseif protocol.stopped
      data = "Stopped"
    elseif protocol.cancelled
      data = "Cancelled"
    elseif protocol.done
      data = "Finished"
    else
      data = "Unknown"
    end
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
    return
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end

function handleEvent(protocol::PNSTestProtocol, event::DatasetStoreStorageRequestEvent)
  # Only handle storage if the protocol completed successfully
  if protocol.cancelled
    put!(protocol.biChannel, IllegaleStateEvent("Protocol was cancelled, cannot save data."))
  else
    # For now, just create a dummy filename since this is a test protocol
    filename = "PNSTestProtocol_$(now()).txt"
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::PNSTestProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::PNSTestProtocol) = Interactive()
protocolMDFStudyUse(protocol::PNSTestProtocol) = UsingMDFStudy()