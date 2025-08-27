export PorridgeProtocol, PorridgeProtocolParams
"""
Parameters for the PorridgeProtocol
"""
Base.@kwdef mutable struct PorridgeProtocolParams <: ProtocolParams
  "Base sequence template to use for measurements"
  sequence::Union{Sequence, Nothing} = nothing
  "Current sequences for each coil (coil_name => [sequence_values...])"
  coilCurrents::Dict{String, Vector{typeof(1.0u"A")}} = Dict{String, Vector{typeof(1.0u"A")}}()
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
  
  # Parse coil currents if provided
  coilCurrents = Dict{String, Vector{typeof(1.0u"A")}}()
  if haskey(dict, "coilCurrents")
    for (coilName, values) in dict["coilCurrents"]
      if values isa Vector{String}
        coilCurrents[coilName] = [parse(Float64, v) * 1.0u"A" for v in values]
      elseif values isa Vector{<:Real}
        coilCurrents[coilName] = [v * 1.0u"A" for v in values]
      else
        coilCurrents[coilName] = values
      end
    end
    delete!(dict, "coilCurrents")
  end
  
  params = params_from_dict(PorridgeProtocolParams, dict)
  params.sequence = sequence
  params.coilCurrents = coilCurrents
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
  
  if isempty(protocol.params.coilCurrents)
    throw(IllegalStateException("Protocol requires coil current sequences in the TOML configuration"))
  end
  
  # Verify all coil sequences have the same length
  sequenceLengths = [length(values) for values in values(protocol.params.coilCurrents)]
  if length(unique(sequenceLengths)) != 1
    throw(IllegalStateException("All coil current sequences must have the same length"))
  end
  
  protocol.sequenceLength = sequenceLengths[1]
  protocol.totalSequences = protocol.sequenceLength
  
  @info "Initialized Porridge protocol with $(protocol.totalSequences) sequence measurements"
  
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentSequenceIndex = 0
  return nothing
end



function timeEstimate(protocol::PorridgeProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence) && !isempty(protocol.params.coilCurrents)
    params = protocol.params
    seq = params.sequence
    framesPerSequence = acqNumFrames(seq) * acqNumFrameAverages(seq) * params.framesPerAmplitude
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    # Use the sequence length from coil currents
    sequenceLength = length(first(values(params.coilCurrents)))
    totalFrames = framesPerSequence * sequenceLength + params.bgFrames
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
    @info "Estimated measurement time: $est for $sequenceLength sequence measurements"
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
    # Measure background first
    @info "Measuring background with zero currents"
    measureSequenceStep(protocol, 0) # Background measurement
    
    # Iterate through all sequence steps
    for step in 1:protocol.sequenceLength
      if protocol.cancelled || protocol.stopped
        @info "Measurement cancelled or stopped at step $step"
        break
      end
      
      protocol.currentSequenceIndex = step
      @info "Measuring sequence step $step/$(protocol.sequenceLength)"
      
      measureSequenceStep(protocol, step)
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

function measureSequenceStep(protocol::PorridgeProtocol, step::Int)
  """Measure magnetic field for a specific step in the current sequences"""
  sequence = createSequenceForStep(protocol.params.sequence, protocol.params.coilCurrents, step)
  daq = getDAQ(protocol.scanner)
  
  setup(daq, sequence)
  startTx(daq)
  timing = getTiming(daq)
  
  # Wait for sequence to complete or handle cancellation
  current = 0
  finish = timing.finish
  
  while current < finish
    current = currentWP(daq.rpc)
    handleEvents(protocol)
    
    if protocol.cancelled || protocol.stopped
      break
    end
    
    sleep(0.01)  # Small sleep to prevent busy waiting
  end
  
  endSequence(daq, finish)
end

function createSequenceForStep(baseSequence::Sequence, coilCurrents::Dict{String, Vector{typeof(1.0u"A")}}, step::Int)
  """Create a sequence with current values for the specified step
  
  Step 0 = background (all currents zero)
  Step 1-N = use the step-th value from each coil's current sequence
  """
  @debug "Creating sequence for step $step"
  
  if step == 0
    @debug "Background step - all currents zero"
  else
    currentValues = Dict{String, typeof(1.0u"A")}()
    for (coilName, currents) in coilCurrents
      currentValues[coilName] = currents[step]
    end
    @debug "Step $step current values: $(length(currentValues)) coils configured"
  end
  
  # TODO: Implement proper sequence modification when needed
  # For now, return the base sequence
  return baseSequence
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
    
    # Store sequence information for ML training data
    if !isempty(protocol.params.coilCurrents)
      write(file, "/totalSequences", protocol.sequenceLength)
      write(file, "/framesPerAmplitude", protocol.params.framesPerAmplitude)
      
      # Create a matrix of current sequences: (sequence_step, coil_number)
      coilNames = sort(collect(keys(protocol.params.coilCurrents)))
      sequenceMatrix = zeros(Float64, protocol.sequenceLength, length(coilNames))
      
      for (coilIndex, coilName) in enumerate(coilNames)
        currents = protocol.params.coilCurrents[coilName]
        for step in 1:length(currents)
          sequenceMatrix[step, coilIndex] = ustrip(u"A", currents[step])
        end
      end
      
      write(file, "/coilNames", coilNames)
      write(file, "/currentSequences", sequenceMatrix)
    end
    
    # write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO only works for LakeShore460 atm
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::PorridgeProtocol) = Interactive()
protocolMDFStudyUse(protocol::PorridgeProtocol) = UsingMDFStudy()
