export PorridgeProtocol, PorridgeProtocolParams
"""
Parameters for the PorridgeProtocol
"""
Base.@kwdef mutable struct PorridgeProtocolParams <: ProtocolParams
  "Base sequence template to use for measurements"
  sequence::Union{Sequence, Nothing} = nothing
  "Current sequences as matrix: (sequence_step, coil_number)"
  coilCurrents::Matrix{typeof(1.0u"A")} = Matrix{typeof(1.0u"A")}(undef, 0, 0)
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
  
  # Parse coil currents matrix if provided
  coilCurrents = Matrix{typeof(1.0u"A")}(undef, 0, 0)
  if haskey(dict, "coilCurrents")
    currentMatrix = dict["coilCurrents"]
    if currentMatrix isa Vector{Vector{<:Real}}
      # Convert nested vectors to matrix with units
      nSteps = length(currentMatrix)
      nCoils = length(currentMatrix[1])
      coilCurrents = Matrix{typeof(1.0u"A")}(undef, nSteps, nCoils)
      for i in 1:nSteps
        for j in 1:nCoils
          coilCurrents[i, j] = currentMatrix[i][j] * 1.0u"A"
        end
      end
    elseif currentMatrix isa Matrix{<:Real}
      # Convert matrix to unitful matrix
      coilCurrents = currentMatrix * 1.0u"A"
    else
      @warn "Unexpected format for coilCurrents, expected matrix or vector of vectors"
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
  
  # Get sequence length from matrix dimensions
  protocol.sequenceLength = size(protocol.params.coilCurrents, 1)  # Number of rows = sequence steps
  protocol.totalSequences = protocol.sequenceLength
  
  nCoils = size(protocol.params.coilCurrents, 2)  # Number of columns = coils
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
  if !isnothing(protocol.params.sequence) && !isempty(protocol.params.coilCurrents)
    params = protocol.params
    seq = params.sequence
    framesPerSequence = acqNumFrames(seq) * acqNumFrameAverages(seq) * params.framesPerAmplitude
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    # Use the sequence length from matrix dimensions
    sequenceLength = size(params.coilCurrents, 1)
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
  sequence = createSequenceForStep(protocol.params.sequence, protocol.params.coilCurrents, step)
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

function createSequenceForStep(baseSequence::Sequence, coilCurrents::Matrix{typeof(1.0u"A")}, step::Int)
  """Create a sequence with current values for the specified step
  
  Step 0 = background (all currents zero)
  Step 1-N = use the step-th row from the current matrix
  """
  @debug "Creating sequence for step $step"
  
  if step == 0
    @debug "Background step - all currents zero"
  else
    # Get current values for this step (row from matrix)
    stepCurrents = coilCurrents[step, :]
    nCoils = length(stepCurrents)
    @debug "Step $step current values: $nCoils coils configured"
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
    
    # Store sequence information for ML training data (PorridgeProtocol extension)
    if !isempty(protocol.params.coilCurrents)
      write(file, "/totalSequences", protocol.sequenceLength)
      write(file, "/framesPerAmplitude", protocol.params.framesPerAmplitude)
      
      # Store the current sequences matrix directly
      sequenceMatrix = ustrip.(u"A", protocol.params.coilCurrents)
      write(file, "/currentSequences", sequenceMatrix)
      
      # Generate coil names for reference
      nCoils = size(protocol.params.coilCurrents, 2)
      coilNames = ["coil$i" for i in 1:nCoils]
      write(file, "/coilNames", coilNames)
    end
    
    # write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO only works for LakeShore460 atm
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::PorridgeProtocol) = Interactive()
protocolMDFStudyUse(protocol::PorridgeProtocol) = UsingMDFStudy()
