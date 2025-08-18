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
  "Amplitudes to iterate over"
  amplitudes::Vector{Unitful.Quantity} = ["0.0001T", "0.0002T", "0.0003T", "0.0004T", "0.0005T", "0.0006T", "0.0007T", "0.0008T", "0.0009T", "0.001T", "0.0011T", "0.0012T", "0.0013T", "0.0014T", "0.0015T", "0.0016T", "0.0017T", "0.0018T", "0.0019T", "0.002T"]
  "Foreground frames to measure per amplitude"
  fgFrames::Int64 = 1
  "Background frames to measure"
  bgFrames::Int64 = 1
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = false
  "If the temperature should be saved or not"
  saveTemperatureData::Bool = false
  "Remember background measurement"
  rememberBGMeas::Bool = false
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

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing
  protocolMeasState::Union{ProtocolMeasState, Nothing} = nothing
  
  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
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
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
  
  # Control system state
  controlSequence::Union{ControlSequence, Nothing} = nothing
  fieldMeasured::Union{Array, Nothing} = nothing
  initialControlDone::Bool = false
  daq::Union{AbstractDAQ, Nothing} = nothing
end

function requiredDevices(protocol::PNSStudyProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  if protocol.params.saveTemperatureData
    push!(result, TemperatureSensor)
  end
  return result
end

function _init(protocol::PNSStudyProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end

  # Extract amplitudes from the sequence
  protocol.amplitudes = [string(amplitude) for amplitude in protocol.params.amplitudes]
  
  if isempty(protocol.amplitudes)
    throw(IllegalStateException("Sequence contains no drive field amplitudes"))
  end

  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  protocol.protocolMeasState = ProtocolMeasState()
  
  # Initialize control system
  protocol.controlSequence = nothing
  protocol.fieldMeasured = nothing
  protocol.initialControlDone = false
  protocol.daq = getDAQ(protocol.scanner)

  return nothing
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
  protocol.measuring = false
  protocol.unit = ""
  protocol.protocolMeasState = ProtocolMeasState()
end

function _execute(protocol::PNSStudyProtocol)
  @debug "PNS Study protocol started"

  protocol.currStep = 0
  index = 1
  
  # Perform initial control at the very start for accurate baseline
  if protocol.params.controlTx && !protocol.initialControlDone
    @info "Performing initial control/calibration..."
    performInitialControl(protocol)
    protocol.initialControlDone = true
  end
  
  # Take background measurement once if needed
  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    
    # Set first amplitude for background measurement
    setAmplitudeForCurrentStep(protocol, index)
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)

    @debug "Taking background measurement."
    protocol.unit = "BG Frames"
    measurement(protocol)
    protocol.bgMeas = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))
    deviceBuffers = protocol.seqMeasState.deviceBuffers
    push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = true)
  end
  
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
    
    @info "PNS Study: Measuring magnetic field amplitude: $currentAmplitude"
    
    # Apply single-shot regulation if we have previous measurement data
    if protocol.params.controlTx && index > 1 && !isnothing(protocol.fieldMeasured)
      @debug "Applying single-shot regulation based on previous measurement"
      applySingleShotRegulation(protocol, index)
    end
    
    # Set the amplitude in the sequence for this measurement
    setAmplitudeForCurrentStep(protocol, index)
    
    # Check for events immediately after starting measurement
    handleEvents(protocol)
    if protocol.cancelled
      throw(CancelException())
    end
    
    # Perform the actual measurement for this amplitude
    @debug "Setting number of foreground frames."
    acqNumFrames(protocol.params.sequence, protocol.params.fgFrames)

    @debug "Starting foreground measurement for amplitude: $currentAmplitude"
    protocol.unit = "Frames"
    measurement(protocol)
    deviceBuffers = protocol.seqMeasState.deviceBuffers
    push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = false)
    
    # Store measured field data for next iteration's regulation
    if protocol.params.controlTx && !isnothing(protocol.seqMeasState)
      protocol.fieldMeasured = extractMeasuredField(protocol)
      @debug "Stored measured field data for regulation: $(protocol.fieldMeasured)"
    end
    
    # Wait for the specified duration after measurement
    @info "Amplitude $currentAmplitude measurement complete. Waiting $(protocol.params.waitTime) seconds..."
    sleepStart = time()
    while time() - sleepStart < protocol.params.waitTime
      # Check for events more frequently for immediate cancellation/pause
      handleEvents(protocol)
      if protocol.cancelled
        throw(CancelException())
      elseif protocol.stopped
        @info "Amplitude test paused during wait period"
        break
      end
      sleep(0.05)  # Shorter sleep for more responsive cancellation/pause
    end
    
    # Check again after wait if we should stop or cancel
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
      
      decision = askChoices(protocol, "Amplitude '$currentAmplitude' measurement completed. How should we proceed?", options)
      protocol.waitingForDecision = false
      
      if decision == length(options)  # "Cancel" (last option)
        @info "PNS Study cancelled by user decision."
        protocol.cancelled = true
        throw(CancelException())
      elseif protocol.params.allowRepeats && decision == 2  # "Repeat" (if enabled)
        @info "Repeating amplitude measurement: $currentAmplitude"
        # Don't increment index, so we repeat the current amplitude
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

function performInitialControl(protocol::PNSStudyProtocol)
  """
  Perform comprehensive control/calibration at the start of PNS study.
  This establishes accurate baseline for all subsequent measurements.
  """
  if isnothing(protocol.txCont)
    @warn "Cannot perform control - TxDAQController not available"
    return
  end
  
  @info "Starting initial control sequence..."
  
  # Create control sequence from the base sequence 
  # Wenn regeln: seq = sequences[i], control_sequence = ControlSequence(txCont,seq)
  seq = protocol.params.sequence
  setup(protocol.daq, seq)
  protocol.controlSequence = ControlSequence(protocol.txCont, seq, protocol.daq)
  
  # Perform the control
  # controlTx(txCont, control_sequence)
  controlTx(protocol.txCont, seq, protocol.controlSequence)
  
  @info "Initial control sequence completed"
end

function applySingleShotRegulation(protocol::PNSStudyProtocol, currentIndex::Int)
  """
  Apply single-shot regulation using previous measurement as feedback.
  This adjusts the next amplitude based on the error from the last measurement.
  """
  if isnothing(protocol.controlSequence) || isnothing(protocol.fieldMeasured) || isnothing(protocol.txCont)
    @warn "Cannot perform single-shot regulation - missing control data"
    return
  end
  
  #try
    # Calculate desired field for the next measurement
    # Wenn Werte anpassen: field_desired = calcDesiredField(ControlSequence(txCont,sequences[i+1])
    nextSeq = deepcopy(protocol.params.sequence)
    setAmplitudeForSequence(nextSeq, protocol.params.amplitudes, currentIndex - 1)
    nextControlSeq = ControlSequence(protocol.txCont, nextSeq, protocol.daq)
    field_desired = calcDesiredField(nextControlSeq)
    @info protocol.fieldMeasured[:, :, end, 1]
    @info field_desired
    
    # Apply control step using measured vs desired field
    # step = controlStep!(control_sequence, txCont, field_measured, field_desired) # alte Sequenz
    step = controlStep!(protocol.controlSequence, protocol.txCont, protocol.fieldMeasured[:, :, 1, 1], field_desired)
    
    if step == INVALID
      @warn "Control step returned INVALID - performing emergency control"
      stop(protocol)
      controlTx(protocol.txCont, protocol.controlSequence)
      @info "Emergency control recalibration completed"
    else
      @debug "Single-shot regulation applied successfully (step: $step)"
    end
    
  #catch e
  #  @error "Error during single-shot regulation: $e"
  #  @warn "Continuing without regulation adjustment"
  #end
end

function setAmplitudeForSequence(seq::Sequence, amplitudes::Vector, index::Int)
  """
  Helper function to set amplitude for a sequence copy.
  """
  amplitudeStr = string(amplitudes[index])
  amplitudeValue = uparse(amplitudeStr)
  
  # Get all drive field channels from the sequence and set their amplitudes
  dfChannels = [channel for field in fields(seq) if field.id == "df" for channel in field.channels]
  
  for channel in dfChannels
    if isa(channel, PeriodicElectricalChannel)
      for component in components(channel)
        if isa(component, PeriodicElectricalComponent)
          # Set the amplitude for the first period (period = 1)
          amplitude!(component, amplitudeValue, period = 1)
        end
      end
    end
  end
end

function extractMeasuredField(protocol::PNSStudyProtocol)
  """
  Extract measured field data from the measurement for use in regulation.
  Returns the actual field values that were measured.
  """
  try
    if !isnothing(protocol.protocolMeasState)
      measuredData = read(protocol.protocolMeasState, DriveFieldBuffer)
      #@debug "Extracted measured field data with size: $(size(measuredData))"
      return measuredData[:, :, :, end:end]
    else
      @warn "No drive field buffer available for field measurement extraction"
      return nothing
    end
  catch e
    @error "Error extracting measured field: $e"
    return nothing
  end
end

function setAmplitudeForCurrentStep(protocol::PNSStudyProtocol, index::Int)
  # Parse the amplitude string back to a value with units
  amplitudeStr = protocol.amplitudes[index]
  amplitudeValue = uparse(amplitudeStr)
  
  # Get all drive field channels from the sequence and set their amplitudes
  dfChannels = [channel for field in fields(protocol.params.sequence) if field.id == "df" for channel in field.channels]
  
  for channel in dfChannels
    if isa(channel, PeriodicElectricalChannel)
      for component in components(channel)
        if isa(component, PeriodicElectricalComponent)
          # Set the amplitude for the first period (period = 1)
          amplitude!(component, amplitudeValue, period = 1)
        end
      end
    end
  end
  
  @debug "Set amplitude to $amplitudeValue for measurement step $index"
end

function measurement(protocol::PNSStudyProtocol)
  # Start async measurement
  protocol.measuring = true
  measState = asyncMeasurement(protocol)
  producer = measState.producer
  consumer = measState.consumer

  # Handle events
  while !istaskdone(consumer)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end
  protocol.measuring = false

  # Check tasks
  ex = nothing
  if Base.istaskfailed(producer)
    currExceptions = current_exceptions(producer)
    @error "Producer failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
  end
  if Base.istaskfailed(consumer)
    currExceptions = current_exceptions(consumer)
    @error "Consumer failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    if isnothing(ex)
      ex = currExceptions[1][:exception]
    end
  end
  if !isnothing(ex)
    throw(ErrorException("Measurement failed, see logged exceptions and stacktraces"))
  end
end

function asyncMeasurement(protocol::PNSStudyProtocol)
  scanner_ = scanner(protocol)
  sequence = protocol.params.sequence
  daq = getDAQ(scanner_)
  deviceBuffer = DeviceBuffer[]
  #if protocol.params.controlTx
  #  sequence = controlTx(protocol.txCont, sequence)
  #  push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
  #end
  setup(daq, sequence)
  protocol.seqMeasState = SequenceMeasState(daq, sequence)
  if protocol.params.saveTemperatureData
    push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner_), acqNumFrames(protocol.params.sequence)))
  end
  protocol.seqMeasState.deviceBuffers = deviceBuffer
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
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
  reply = nothing
  if !isnothing(protocol.seqMeasState) && protocol.measuring
    framesTotal = protocol.seqMeasState.numFrames
    framesDone = min(index(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, framesTotal)
    reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  else
    reply = ProgressEvent(protocol.currStep, length(protocol.amplitudes), "Amplitude", event)
  end
  put!(protocol.biChannel, reply)
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
      data = "Measuring amplitude"
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
  elseif event.message == "CONTROL_STATUS"
    if protocol.params.controlTx
      if protocol.initialControlDone
        data = "Control active (initial calibration completed)"
      else
        data = "Control enabled (awaiting initial calibration)"
      end
    else
      data = "Control disabled"
    end
  elseif event.message == "FIELD_MEASURED"
    data = protocol.fieldMeasured
  elseif event.message == "CURRFRAME" && !isnothing(protocol.seqMeasState)
    data = max(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, 0)
  elseif startswith(event.message, "FRAME") && !isnothing(protocol.seqMeasState)
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.seqMeasState.numFrames
        data = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER" && !isnothing(protocol.seqMeasState)
    data = copy(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)))
  elseif event.message == "BG"
    if length(protocol.bgMeas) > 0
      data = copy(protocol.bgMeas)
    else
      data = nothing
    end
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
    store = event.datastore
    scanner = protocol.scanner
    mdf = event.mdf
    data = read(protocol.protocolMeasState, MeasurementBuffer)
    isBGFrame = measIsBGFrame(protocol.protocolMeasState)
    drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
    appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
    temperature = read(protocol.protocolMeasState, TemperatureBuffer)
    filename = saveasMDF(store, scanner, protocol.params.sequence, data, isBGFrame, mdf, drivefield = drivefield, temperatures = temperature, applied = appliedField)
    @info "The PNS Study measurement was saved at `$filename`."
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::PNSStudyProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::PNSStudyProtocol) = Interactive()
protocolMDFStudyUse(protocol::PNSStudyProtocol) = UsingMDFStudy()
