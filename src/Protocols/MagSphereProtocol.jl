export MagSphereProtocol, MagSphereProtocolParams
"""
Parameters for the MagSphereProtocol
"""
Base.@kwdef mutable struct MagSphereProtocolParams <: ProtocolParams
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
end
function MagSphereProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(MagSphereProtocolParams, dict)
  params.sequence = sequence
  return params
end
MagSphereProtocolParams(dict::Dict) = params_from_dict(MagSphereProtocolParams, dict)

Base.@kwdef mutable struct MagSphereProtocol <: Protocol
  @add_protocol_fields MagSphereProtocolParams


  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  unit::String = ""
  fieldData::Vector{MagSphereResult} = MagSphereResult[]
  consumer::Union{Task,Nothing} = nothing
end

function requiredDevices(protocol::MagSphereProtocol)
  result = [AbstractDAQ,MagSphere]
  return result
end

function _init(protocol::MagSphereProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  return nothing
end

function timeEstimate(protocol::MagSphereProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence)
    params = protocol.params
    seq = params.sequence
    totalFrames = acqNumFrames(seq) * acqNumFrameAverages(seq)
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
    @show est
  end
  return est
end

function enterExecute(protocol::MagSphereProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.unit = ""
  protocol.fieldData = MagSphereResult[]
end

function _execute(protocol::MagSphereProtocol)
  @debug "Measurement protocol started"

  performExperiment(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
end

function performExperiment(protocol::MagSphereProtocol)
  # Start async measurement
  protocol.measuring = true

  sequence = protocol.params.sequence
  daq = getDAQ(protocol.scanner)

  setup(daq, sequence)

  su = getSurveillanceUnit(protocol.scanner)

  if !isnothing(su)
    enableACPower(su)
  end

  #Start Capturing MagSphere Data
  magSphere = getDevice(protocol.scanner,MagSphere)
  enable(magSphere)
  protocol.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(protocol)

  startTx(daq)
  timing = getTiming(daq)

  # Handle events
  current = 0
  finish = timing.finish # time when the sequence is finished
  while current < timing.finish # do as long as the sequence is not finished
    current = currentWP(daq.rpc) # current write pointer
    handleEvents(protocol)
    if protocol.cancelled || protocol.stopped # in case the user want to stop the measurement even though the mearuement is not yet finished
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
  
  disable(magSphere)

  # TODO Do the following in finally block
  endSequence(daq, finish)

  if !isnothing(su)
    disableACPower(su)
  end

  protocol.measuring = false

  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEven()))
  end
  if protocol.cancelled
    throw(CancelException())
  end
end

function asyncConsumer(protocol::MagSphereProtocol)
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

function cleanup(protocol::MagSphereProtocol)
  # NOP
end

function stop(protocol::MagSphereProtocol)
  protocol.stopped = true
end

function resume(protocol::MagSphereProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MagSphereProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::MagSphereProtocol, event::ProgressQueryEvent)
  reply = nothing
  framesTotal = acqNumFrames(protocol.params.sequence)
  framesDone = protocol.measuring ? currentFrame(getDAQ(protocol.scanner)) : 0
  reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::MagSphereProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MagSphereProtocol, event::FileStorageRequestEvent)
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
    # write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO only works for LakeShore460 atm
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MagSphereProtocol) = Interactive()
protocolMDFStudyUse(protocol::MagSphereProtocol) = UsingMDFStudy()
