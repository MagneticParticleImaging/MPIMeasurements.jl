export PNSStudyProtocol, PNSStudyProtocolParams
using Dates

"""
Parameters for the PNSStudyProtocol
"""
Base.@kwdef mutable struct PNSStudyProtocolParams <: ProtocolParams
  "Sequence to use for PNS study measurements"
  sequence::Union{Sequence, Nothing} = nothing
  "Time duration for each magnetic field amplitude (seconds)"
  waitTime::Float64 = 2.0
  "Allow repeating measurements for the same amplitude"
  allowRepeats::Bool = true
end

function PNSStudyProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(PNSStudyProtocolParams, dict)
  params.sequence = sequence
  return params
end
PNSStudyProtocolParams(dict::Dict) = params_from_dict(PNSStudyProtocolParams, dict)

Base.@kwdef mutable struct PNSStudyProtocol <: Protocol
  @add_protocol_fields PNSStudyProtocolParams

  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  stopped::Bool = false
  restored::Bool = false
  measuring::Bool = false
  currStep::Int = 0
  currentAmplitude::String = ""
  waitingForDecision::Bool = false
  amplitudes::Vector{String} = String[]
end

function requiredDevices(protocol::PNSStudyProtocol)
  result = []
  return result
end

function _init(protocol::PNSStudyProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end

  # Extract amplitudes from the sequence
  protocol.amplitudes = extractAmplitudes(protocol.params.sequence)
  
  if isempty(protocol.amplitudes)
    throw(IllegalStateException("Sequence contains no drive field amplitudes"))
  end

  return nothing
end

function extractAmplitudes(sequence::Sequence)::Vector{String}
  amplitudes = String[]
  
  # Get all drive field channels from the sequence
  dfChannels = [channel for field in fields(sequence) if field.id == "df" for channel in field.channels]
  
  if isempty(dfChannels)
    return amplitudes
  end
  
  # Get the first periodic electrical channel and extract amplitudes
  for channel in dfChannels
    if isa(channel, PeriodicElectricalChannel)
      for component in components(channel)
        if isa(component, PeriodicElectricalComponent)
          for amp in component.amplitude
            # Format amplitude as string with proper units
            amp_str = string(amp)
            if !(amp_str in amplitudes)
              push!(amplitudes, amp_str)
            end
          end
        end
      end
    end
  end
  
  return amplitudes
end

function timeEstimate(protocol::PNSStudyProtocol)
  numAmplitudes = length(protocol.amplitudes)
  totalTime = numAmplitudes * protocol.params.waitTime
  est = "≈ $(round(totalTime, digits=1)) seconds"
  return est
end

function enterExecute(protocol::PNSStudyProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.measuring = true
end

function _execute(protocol::PNSStudyProtocol)
  @debug "PNS Study protocol started"

  protocol.currStep = 0
  index = 1
  remainingWaitTime = 0.0  # Track remaining time when paused
  
  while index <= length(protocol.amplitudes) && !protocol.cancelled
    # Handle pause/resume logic
    notifiedStop = false
    while protocol.stopped
      handleEvents(protocol)
      # Throw CancelException immediately when cancelled to terminate thread
      if protocol.cancelled
        throw(CancelException())
      end
      if !notifiedStop
        put!(protocol.biChannel, OperationSuccessfulEvent(PauseEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
    
    # Check if we should cancel
    if protocol.cancelled
      throw(CancelException())
    end
    
    protocol.currStep = index
    currentAmplitude = protocol.amplitudes[index]
    protocol.currentAmplitude = currentAmplitude
    
    @info "PNS Study: Testing magnetic field amplitude: $currentAmplitude"
    
    # Check for events immediately after starting measurement
    handleEvents(protocol)
    if protocol.cancelled
      throw(CancelException())
    end
    
    # Determine wait time - use remaining time if resuming, otherwise use fixed wait time
    if remainingWaitTime > 0.0
      waitTime = remainingWaitTime
      remainingWaitTime = 0.0
      @info "Resuming amplitude test with $(round(waitTime, digits=2)) seconds remaining"
    else
      # Use fixed wait time for consistent amplitude exposure duration
      waitTime = protocol.params.waitTime
    end
    
    # Sleep with cancellation and pause checks - more responsive 
    sleepStart = time()
    while time() - sleepStart < waitTime
      # Check for events more frequently for immediate cancellation/pause
      handleEvents(protocol)
      if protocol.cancelled
        throw(CancelException())
      elseif protocol.stopped
        # Calculate remaining time when paused
        remainingWaitTime = waitTime - (time() - sleepStart)
        @info "Amplitude test paused with $(round(remainingWaitTime, digits=2)) seconds remaining"
        break
      end
      sleep(0.05)  # Shorter sleep for more responsive cancellation/pause
    end
    
    # Check again after sleep if we should stop or cancel
    if protocol.cancelled
      throw(CancelException())  # Immediately terminate thread
    elseif protocol.stopped
      continue  # Go back to pause/resume handling
    end
    
    # Ask for decision after each amplitude test (except the last one)
    if index < length(protocol.amplitudes)
      protocol.waitingForDecision = true
      
      # Check for cancellation before asking for decision
      handleEvents(protocol)
      if protocol.cancelled
        protocol.waitingForDecision = false
        throw(CancelException())
      end
      
      options = ["Continue", "Cancel"]
      if protocol.params.allowRepeats
        options = ["Continue", "Repeat", "Cancel"]
      end
      
      decision = askChoices(protocol, "Amplitude '$currentAmplitude' test completed. How should we proceed?", options)
      protocol.waitingForDecision = false
      
      if decision == length(options)  # "Cancel" (last option)
        @info "PNS Study cancelled by user decision."
        protocol.cancelled = true
        throw(CancelException())
      elseif protocol.params.allowRepeats && decision == 2  # "Repeat" (if enabled)
        @info "Repeating amplitude test: $currentAmplitude"
        # Don't increment index, so we repeat the current amplitude
        # Reset remaining time so the test gets a fresh fixed wait time
        remainingWaitTime = 0.0
        continue
      else  # decision == 1, "Continue"
        @info "Continuing to next amplitude."
      end
    end
    
    # Move to next amplitude
    index += 1
  end

  if !protocol.cancelled
    protocol.done = true
    @info "PNS Study protocol finished successfully."
  else
    @info "PNS Study protocol was cancelled."
  end
  
  # Always send FinishedNotificationEvent, even if cancelled
  put!(protocol.biChannel, FinishedNotificationEvent())
  
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    # Don't throw CancelException here anymore - we've already thrown it above
    sleep(0.05)
  end
  
  @info "PNS Study protocol finished."
  close(protocol.biChannel)
  @debug "PNS Study protocol channel closed after execution."
end

function cleanup(protocol::PNSStudyProtocol)

end

function stop(protocol::PNSStudyProtocol)
    protocol.stopped = true
    protocol.restored = false
    protocol.measuring = false
    @info "PNS Study protocol paused."
end

function resume(protocol::PNSStudyProtocol)
  protocol.stopped = false
  protocol.restored = true
  protocol.measuring = true
  @info "PNS Study protocol resumed."
end

function cancel(protocol::PNSStudyProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropriate
  protocol.stopped = true # Set stop to reach a known/safe state
end

function handleEvent(protocol::PNSStudyProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel, ProgressEvent(protocol.currStep, length(protocol.amplitudes), "Amplitude", event))
end

function handleEvent(protocol::PNSStudyProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURR"
    data = protocol.currentAmplitude
  elseif event.message == "STEP"
    data = protocol.currStep
  elseif event.message == "TOTAL"
    data = length(protocol.amplitudes)
  elseif event.message == "STATUS"
    if protocol.waitingForDecision
      data = "Waiting for decision"
    elseif protocol.measuring
      data = "Testing amplitude"
    elseif protocol.stopped
      data = "Stopped"
    elseif protocol.cancelled
      data = "Cancelled"
    elseif protocol.done
      data = "Finished"
    else
      data = "Unknown"
    end
  elseif event.message == "AMPLITUDES"
    data = protocol.amplitudes
  elseif event.message == "SEQUENCE"
    data = isnothing(protocol.params.sequence) ? "None" : name(protocol.params.sequence)
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
    return
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end

function handleEvent(protocol::PNSStudyProtocol, event::DatasetStoreStorageRequestEvent)
  # Only handle storage if the protocol completed successfully
  if protocol.cancelled
    # Don't log error, just silently skip storage for cancelled protocols
    return
  else
    # For now, just create a dummy filename since this is a PNS study protocol
    filename = "PNSStudyProtocol_$(now()).txt"
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::PNSStudyProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::PNSStudyProtocol) = Interactive()
protocolMDFStudyUse(protocol::PNSStudyProtocol) = UsingMDFStudy()
