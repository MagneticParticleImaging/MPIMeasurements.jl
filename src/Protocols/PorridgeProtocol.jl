export PorridgeProtocol, PorridgeProtocolParams
"""
Parameters for the PorridgeProtocol
"""
Base.@kwdef mutable struct PorridgeProtocolParams <: ProtocolParams
  "Base sequence template to use for measurements"
  sequence::Union{Sequence, Nothing} = nothing
  "Current vectors for each of the 18 coils"
  coil1Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil2Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil3Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil4Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil5Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil6Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil7Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil8Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil9Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil10Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil11Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil12Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil13Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil14Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil15Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil16Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil17Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  coil18Currents::Vector{typeof(1.0u"A")} = typeof(1.0u"A")[]
  "Number of frames per sequence measurement"
  framesPerAmplitude::Int = 1
  "Background frames"
  bgFrames::Int = 1
end
function PorridgeProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  
  # Parse individual coil current vectors
  coilNames = ["coil$(i)Currents" for i in 1:18]
  for coilName in coilNames
    if haskey(dict, coilName)
      currentVector = dict[coilName]
      if currentVector isa Vector{Float64}
        dict[coilName] = currentVector * 1.0u"A"
      else
        @warn "Unexpected format for $coilName, expected vector of floats"
      end
    end
  end
  
  params = params_from_dict(PorridgeProtocolParams, dict)
  params.sequence = sequence
  return params
end
PorridgeProtocolParams(dict::Dict) = params_from_dict(PorridgeProtocolParams, dict)

Base.@kwdef mutable struct PorridgeProtocol <: Protocol
  @add_protocol_fields PorridgeProtocolParams

  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  unit::String = ""
  fieldData::Vector{MagSphereResult} = MagSphereResult[]
  consumer::Union{Task,Nothing} = nothing
  currentSequenceIndex::Int = 0
  totalSequences::Int = 0
  sequenceLength::Int = 0
end

function requiredDevices(protocol::PorridgeProtocol)
  result = [AbstractDAQ,MagSphere]
  return result
end

function _init(protocol::PorridgeProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  
  # Check if we have any coil currents defined
  coilVectors = [protocol.params.coil1Currents, protocol.params.coil2Currents, 
                 protocol.params.coil3Currents, protocol.params.coil4Currents,
                 protocol.params.coil5Currents, protocol.params.coil6Currents,
                 protocol.params.coil7Currents, protocol.params.coil8Currents,
                 protocol.params.coil9Currents, protocol.params.coil10Currents,
                 protocol.params.coil11Currents, protocol.params.coil12Currents,
                 protocol.params.coil13Currents, protocol.params.coil14Currents,
                 protocol.params.coil15Currents, protocol.params.coil16Currents,
                 protocol.params.coil17Currents, protocol.params.coil18Currents]
  
  if all(isempty, coilVectors)
    throw(IllegalStateException("Protocol requires coil current sequences in the TOML configuration"))
  end
  
  # Get sequence length from first non-empty coil vector
  protocol.sequenceLength = 0
  for coilVector in coilVectors
    if !isempty(coilVector)
      protocol.sequenceLength = length(coilVector)
      break
    end
  end
  
  if protocol.sequenceLength == 0
    throw(IllegalStateException("No valid coil current sequences found"))
  end
  
  # Verify all non-empty vectors have the same length
  for (i, coilVector) in enumerate(coilVectors)
    if !isempty(coilVector) && length(coilVector) != protocol.sequenceLength
      throw(IllegalStateException("Coil $(i) current vector length $(length(coilVector)) does not match expected length $(protocol.sequenceLength)"))
    end
  end
  
  protocol.totalSequences = protocol.sequenceLength
  nCoils = sum(!isempty, coilVectors)
  @info "Initialized Porridge protocol with $(protocol.totalSequences) sequence measurements for $nCoils coils"
  
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentSequenceIndex = 0
  return nothing
end



function timeEstimate(protocol::PorridgeProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence)
    params = protocol.params
    seq = params.sequence
    framesPerSequence = acqNumFrames(seq) * acqNumFrameAverages(seq) * params.framesPerAmplitude
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    
    # Get sequence length from first non-empty coil vector
    sequenceLength = 0
    coilVectors = [params.coil1Currents, params.coil2Currents, 
                   params.coil3Currents, params.coil4Currents,
                   params.coil5Currents, params.coil6Currents,
                   params.coil7Currents, params.coil8Currents,
                   params.coil9Currents, params.coil10Currents,
                   params.coil11Currents, params.coil12Currents,
                   params.coil13Currents, params.coil14Currents,
                   params.coil15Currents, params.coil16Currents,
                   params.coil17Currents, params.coil18Currents]
    
    for coilVector in coilVectors
      if !isempty(coilVector)
        sequenceLength = length(coilVector)
        break
      end
    end
    
    if sequenceLength > 0
      totalFrames = framesPerSequence * sequenceLength + params.bgFrames
      totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
      time = totalTime * 1u"s"
      est = string(time)
      @info "Estimated measurement time: $est for $sequenceLength sequence measurements"
    end
  end
  return est
end

function enterExecute(protocol::PorridgeProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.unit = "sequence"
  protocol.fieldData = MagSphereResult[]
  protocol.currentSequenceIndex = 0
end

function _execute(protocol::PorridgeProtocol)
  @debug "Measurement protocol started"

  performExperiment(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
end

function performExperiment(protocol::PorridgeProtocol)
  @info "Starting Porridge experiment"
  protocol.measuring = true

  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  magSphere = getDevice(protocol.scanner, MagSphere)

  if !isnothing(su)
    enableACPower(su)
  end

  # Start capturing MagSphere data
  enable(magSphere)
  protocol.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(protocol)

  try
    # Measure background first (step 0)
    @info "Measuring background with zero currents"
    performSingleMeasurement(protocol, 0)
    
    # Iterate through all sequence steps
    for step in 1:protocol.sequenceLength
      if protocol.cancelled || protocol.stopped
        @info "Measurement cancelled or stopped at step $step"
        break
      end
      
      protocol.currentSequenceIndex = step
      @info "Measuring sequence step $step/$(protocol.sequenceLength)"
      
      performSingleMeasurement(protocol, step)
      handleEvents(protocol)
    end
    
  finally
    disable(magSphere)
    
    if !isnothing(su)
      disableACPower(su)
    end
    
    protocol.measuring = false
  end

  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
  end
  if protocol.cancelled
    throw(CancelException())
  end
end

function performSingleMeasurement(protocol::PorridgeProtocol, step::Int)
  """Perform a single measurement for the given sequence step (similar to MagSphereProtocol)"""
  sequence = createSequenceForStep(protocol, step)
  daq = getDAQ(protocol.scanner)
  
  setup(daq, sequence)
  startTx(daq)
  timing = getTiming(daq)
  
  # Handle events (copied from MagSphereProtocol logic)
  current = 0
  finish = timing.finish # time when the sequence is finished
  while current < timing.finish # do as long as the sequence is not finished
    current = currentWP(daq.rpc) # current write pointer
    handleEvents(protocol)
    if protocol.cancelled || protocol.stopped # in case the user want to stop the measurement even though the measurement is not yet finished
      # TODO move to function of daq
      execute!(daq.rpc) do batch
        for idx in daq.rampingChannel
          @add_batch batch enableRampDown!(daq.rpc, idx, true)
        end
      end
      while !rampDownDone(daq.rpc)
        handleEvents(protocol)
      end
      finish = current
      break
    end
  end
  
  # TODO Do the following in finally block
  endSequence(daq, finish)
end

function createSequenceForStep(protocol::PorridgeProtocol, step::Int)
  """Create a sequence with current values for the specified step
  
  Step 0 = background (all currents zero)
  Step 1-N = use the step-th index from each coil's current vector
  """
  @debug "Creating sequence for step $step"
  
  baseSequence = protocol.params.sequence
  
  # Get all coil current vectors
  coilVectors = [protocol.params.coil1Currents, protocol.params.coil2Currents, 
                 protocol.params.coil3Currents, protocol.params.coil4Currents,
                 protocol.params.coil5Currents, protocol.params.coil6Currents,
                 protocol.params.coil7Currents, protocol.params.coil8Currents,
                 protocol.params.coil9Currents, protocol.params.coil10Currents,
                 protocol.params.coil11Currents, protocol.params.coil12Currents,
                 protocol.params.coil13Currents, protocol.params.coil14Currents,
                 protocol.params.coil15Currents, protocol.params.coil16Currents,
                 protocol.params.coil17Currents, protocol.params.coil18Currents]
  
  # Create a modified copy of the sequence
  modifiedSequence = deepcopy(baseSequence)
  
  # Modify each coil's current value
  for (coilIndex, coilVector) in enumerate(coilVectors)
    if !isempty(coilVector)
      # Determine current value for this step
      currentValue = if step == 0
        0.0u"A"  # Background - zero current
      elseif step <= length(coilVector)
        coilVector[step]
      else
        0.0u"A"  # If step exceeds vector length, use zero
      end
      
      # Apply current to the corresponding coil channel in the sequence
      coilName = "coil$coilIndex"
      applyCurrentToSequence!(modifiedSequence, coilName, currentValue)
      
      @debug "Step $step: Set $coilName current to $currentValue"
    end
  end
  
  return modifiedSequence
end

function applyCurrentToSequence!(sequence::Sequence, coilName::String, currentValue)
  """Apply current value to the specified coil in the sequence"""
  # Look for the coil in all field cages
  for (cageName, cageDict) in sequence.fields
    if haskey(cageDict, coilName)
      coilChannel = cageDict[coilName]
      if hasfield(typeof(coilChannel), :values)
        # For StepwiseElectricalChannel, modify the values array
        coilChannel.values = [string(currentValue)]
        @debug "Applied $currentValue to $cageName.$coilName"
      else
        @debug "Coil channel $cageName.$coilName does not have values field"
      end
    end
  end
end

function asyncConsumer(protocol::PorridgeProtocol)
  magSphere = getDevice(protocol.scanner,MagSphere)
  ch = magSphere.ch
  while isopen(ch) || isready(ch)
    if isready(ch)
      data = take!(ch)
      push!(protocol.fieldData, data)
    end
    sleep(0.01)  # take more often that data is produced
  end
end

function cleanup(protocol::PorridgeProtocol)
  # NOP
end

function stop(protocol::PorridgeProtocol)
  protocol.stopped = true
end

function resume(protocol::PorridgeProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::PorridgeProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::PorridgeProtocol, event::ProgressQueryEvent)
  reply = nothing
  sequencesTotal = protocol.totalSequences
  sequencesDone = protocol.currentSequenceIndex
  reply = ProgressEvent(sequencesDone, sequencesTotal, protocol.unit, event)
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::PorridgeProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::PorridgeProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  magSphere = getDevice(protocol.scanner,MagSphere)
  h5open(filename, "w") do file
    data = cat(map(x-> x.data, protocol.fieldData)..., dims = 3)
    data=permutedims(data,(2,1,3))
    for frame = 1:size(data,3)
      for sensor = 1:size(data,1)
        data[sensor,:,frame] = magSphere.calibrationRotation[sensor,:,:] * data[sensor,:,frame] + magSphere.calibrationOffset[sensor,:] .*u"T"
      end
    end
    write(file,"/fields", ustrip.(u"T", data)) 		# measured field (size: 3 x #points x #patches)
    write(file,"/positions/tDesign/radius", ustrip(u"m", magSphere.params.radius))	# radius of the measured ball
    write(file,"/positions/tDesign/N", magSphere.params.N)		# number of points of the t-design
    write(file,"/positions/tDesign/t", magSphere.params.t)		# t of the t-design
    write(file,"/positions/tDesign/center",  [0.0, 0.0, 0.0])	# center of the measured ball
    write(file,"/timeStamp", map(x -> x.timestamp, protocol.fieldData)) # timeStamp for the corresponding measured field 
    write(file,"/calibrationOffset", magSphere.calibrationOffset)		# calibration data from toml (size(N,3))
    write(file,"/calibrationRotation", magSphere.calibrationRotation)		# calibration data from toml (size(N,3,3))
    
    # Store sequence information for ML training data (PorridgeProtocol extension)
    write(file, "/totalSequences", protocol.sequenceLength)
    write(file, "/framesPerAmplitude", protocol.params.framesPerAmplitude)
    
    # Convert individual coil vectors back to a matrix for storage
    coilVectors = [protocol.params.coil1Currents, protocol.params.coil2Currents, 
                   protocol.params.coil3Currents, protocol.params.coil4Currents,
                   protocol.params.coil5Currents, protocol.params.coil6Currents,
                   protocol.params.coil7Currents, protocol.params.coil8Currents,
                   protocol.params.coil9Currents, protocol.params.coil10Currents,
                   protocol.params.coil11Currents, protocol.params.coil12Currents,
                   protocol.params.coil13Currents, protocol.params.coil14Currents,
                   protocol.params.coil15Currents, protocol.params.coil16Currents,
                   protocol.params.coil17Currents, protocol.params.coil18Currents]
    
    # Create matrix from individual vectors (sequence_step × coil_number)
    if protocol.sequenceLength > 0
      sequenceMatrix = zeros(Float64, protocol.sequenceLength, 18)
      for (coilIndex, coilVector) in enumerate(coilVectors)
        if !isempty(coilVector)
          for stepIndex in 1:min(length(coilVector), protocol.sequenceLength)
            sequenceMatrix[stepIndex, coilIndex] = ustrip(u"A", coilVector[stepIndex])
          end
        end
      end
      write(file, "/currentSequences", sequenceMatrix)
      
      # Generate coil names for reference
      coilNames = ["coil$i" for i in 1:18]
      write(file, "/coilNames", coilNames)
    end
    
    # write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO only works for LakeShore460 atm
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::PorridgeProtocol) = Interactive()
protocolMDFStudyUse(protocol::PorridgeProtocol) = UsingMDFStudy()
