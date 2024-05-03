export MPSSystemMatrixProtocol, MPSSystemMatrixProtocolParams
"""
Parameters for the MPSSystemMatrixProtocol
"""
Base.@kwdef mutable struct MPSSystemMatrixProtocolParams <: ProtocolParams
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = false
  "Number of BG frames"
  bgFrames::Int64 = 0
  "Remember background measurement"
  rememberBGMeas::Bool = false
  "If the temperature should be safed or not"
  saveTemperatureData::Bool = false
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
  "Sort patches"
  sortPatches::Bool = true
  "Flag if the measurement should be saved as a system matrix or not"
  saveAsSystemMatrix::Bool = true

  "Number of periods to be averaged per offset. Overwrites parts of the sequence definition."
  dfPeriodsPerOffset::Integer = 2
end
function MPSSystemMatrixProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence_ = nothing
  if haskey(dict, "sequence")
    sequence_ = Sequence(scanner, dict["sequence"])
    delete!(dict, "sequence")
  end
  
  params = params_from_dict(MPSSystemMatrixProtocolParams, dict)
  params.sequence = sequence_

  return params
end
MPSSystemMatrixProtocolParams(dict::Dict) = params_from_dict(MPSSystemMatrixProtocolParams, dict)

Base.@kwdef mutable struct MPSSystemMatrixProtocol <: AbstractMPSProtocol
  @add_protocol_fields MPSSystemMatrixProtocolParams

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing
  protocolMeasState::Union{ProtocolMeasState, Nothing} = nothing

  sequence::Union{Sequence, Nothing} = nothing 
  offsetfields::Union{Matrix{Float64}, Nothing} = nothing
  patchPermutation::Vector{Union{Int64, Nothing}} = Union{Int64, Nothing}[]
  calibsize::Vector{Int64} = Int64[]

  bgMeas::Array{Float32, 4} = zeros(Float32,0,0,0,0)
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  measuringBG::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
end

function requiredDevices(protocol::MPSSystemMatrixProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::MPSSystemMatrixProtocol)
  #if isnothing(sequence(protocol))
  #  throw(IllegalStateException("Protocol requires a sequence"))
  #end
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  protocol.bgMeas = zeros(Float32,0,0,0,0)
  protocol.protocolMeasState = ProtocolMeasState()

  try
    seq, patchPerm, offsets, calibsize = generateMPSSequence(protocol.params.sequence, getDAQ(scanner(protocol)); numPeriodsPerOffset = protocol.params.dfPeriodsPerOffset,
        sortPatches = protocol.params.sortPatches, averagePeriodsPerOffset = true)

    protocol.sequence = seq
    protocol.patchPermutation = patchPerm
    protocol.offsetfields = offsets
    protocol.calibsize = calibsize
  catch e
    throw(e)
  end

  return nothing
end

function timeEstimate(protocol::MPSSystemMatrixProtocol)
  est = "Unknown"
  if !isnothing(sequence(protocol))
    params = protocol.params
    seq = sequence(protocol)
    fgFrames = acqNumFrameAverages(seq)
    bgFrames = params.measureBackground*params.bgFrames * acqNumFrameAverages(seq)
    txSamplesPerFrame = lcm(dfDivider(seq)) * size(protocol.patchPermutation, 1)
    fgTime = (txSamplesPerFrame * fgFrames) / txBaseFrequency(seq) |> u"s"
    bgTime = dfCycle(seq) * protocol.params.measureBackground * protocol.params.bgFrames |> u"s"
    function timeFormat(t)
      v = ustrip(u"s",t)
      if v>3600  
        x = Int((v%3600)÷60)
        return "$(Int(v÷3600)):$(if x<10; " " else "" end)$(x) h"
      elseif v>60
        x = round(v%60,digits=1)
        return "$(Int(v÷60)):$(if x<10; " " else "" end)$(x) min"
      elseif v>0.5
        return "$(round(v,digits=2)) s"
      elseif v>0.5e-3
        return "$(round(v*1e3,digits=2)) ms"
      else
        return "$(round(v*1e6,digits=2)) µs"
      end
    end 
    perc_wait = round(Int,sum(isnothing.(protocol.patchPermutation))/size(protocol.patchPermutation,1)*100)
    est = "FG: $(timeFormat(fgTime)) ($(perc_wait)% waiting), BG: $(timeFormat(bgTime))"
    @info "The estimated duration is FG: $fgTime ($(perc_wait)% waiting), BG: $bgTime."
  end
  return est
end

function enterExecute(protocol::MPSSystemMatrixProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
end

function _execute(protocol::MPSSystemMatrixProtocol)
  @debug "Measurement protocol started"

  performMeasurement(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function performMeasurement(protocol::MPSSystemMatrixProtocol)
  protocol.measuringBG = true
  performBGMeasurement(protocol)
  @debug "Starting foreground measurement."
  protocol.unit = "Offsets"
  protocol.measuringBG = false
  measurement(protocol, protocol.sequence)
  deviceBuffers = protocol.seqMeasState.deviceBuffers
  push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = false)
end

function performBGMeasurement(protocol::MPSSystemMatrixProtocol)
  if (length(protocol.bgMeas) == 0 || !protocol.params.rememberBGMeas) && protocol.params.measureBackground && protocol.params.bgFrames > 0
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end

    sequence = generateMPSBGSequence(protocol.params.sequence; numBGFrames = protocol.params.bgFrames, numPeriodsPerOffset = protocol.params.dfPeriodsPerOffset)

    @debug "Taking background measurement."
    measurement(protocol, sequence; isBGMeas = true)
    protocol.bgMeas = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))
    deviceBuffers = protocol.seqMeasState.deviceBuffers
    push!(protocol.protocolMeasState, vcat(sinks(protocol.seqMeasState.sequenceBuffer), isnothing(deviceBuffers) ? SinkBuffer[] : deviceBuffers), isBGMeas = true)
    if askChoices(protocol, "Press continue when foreground measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
  end

end

function measurement(protocol::MPSSystemMatrixProtocol, sequence::Sequence; kwargs...)
  # Start async measurement
  protocol.measuring = true
  measState = asyncMeasurement(protocol, sequence; kwargs...)
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

function asyncMeasurement(protocol::MPSSystemMatrixProtocol, sequence::Sequence; isBGMeas::Bool = false)
  scanner_ = scanner(protocol)    
  if isBGMeas
    daq = getDAQ(scanner_)
    deviceBuffer = DeviceBuffer[]
    if protocol.params.controlTx
      sequence = controlTx(protocol.txCont, sequence)
      push!(deviceBuffer, TxDAQControllerBuffer(protocol.txCont, sequence))
    end
    setup(daq, sequence)
    protocol.seqMeasState = SequenceMeasState(daq, sequence)
    if protocol.params.saveTemperatureData
      push!(deviceBuffer, TemperatureBuffer(getTemperatureSensor(scanner_), acqNumFrames(protocol.params.sequence)))
    end
  else  
    sequence, protocol.seqMeasState = SequenceMeasState(protocol, sequence; protocol.patchPermutation, averages = protocol.params.dfPeriodsPerOffset, txCont = protocol.params.controlTx ? protocol.txCont : nothing)
  end
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
end

function cleanup(protocol::MPSSystemMatrixProtocol)
  # NOP
end

function stop(protocol::MPSSystemMatrixProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(StopEvent()))
end

function resume(protocol::MPSSystemMatrixProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MPSSystemMatrixProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::MPSSystemMatrixProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURRFRAME"
    data = max(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, 0)
  elseif startswith(event.message, "FRAME")
    frame = tryparse(Int64, split(event.message, ":")[2])
    if !isnothing(frame) && frame > 0 && frame <= protocol.seqMeasState.numFrames
        data = read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer))[:, :, :, frame:frame]
    end
  elseif event.message == "BUFFER"
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


function handleEvent(protocol::MPSSystemMatrixProtocol, event::ProgressQueryEvent)
  reply = nothing
  if !isnothing(protocol.seqMeasState)
    framesTotal = protocol.seqMeasState.numFrames
    if protocol.measuringBG
      framesDone = min(index(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)) - 1, framesTotal)
    else
      measFramesDone = protocol.seqMeasState.sequenceBuffer.target.counter-1
      framesDone = length(unique(protocol.patchPermutation[1:measFramesDone]))-1
    end
    reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  else
    reply = ProgressEvent(0, 0, "N/A", event)
  end
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::MPSSystemMatrixProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::MPSSystemMatrixProtocol, event::DatasetStoreStorageRequestEvent)
  store = event.datastore
  scanner = protocol.scanner
  sequence = protocol.sequence
  mdf = event.mdf

  data = read(protocol.protocolMeasState, MeasurementBuffer)
  
  periodsPerOffset = size(protocol.patchPermutation,1)÷size(protocol.offsetfields,1)

  offsetPerm = zeros(Int64, size(data, 4) - protocol.params.measureBackground * protocol.params.bgFrames)
  for (index, patch) in enumerate(protocol.patchPermutation)
    if !isnothing(patch)
      offsetPerm[patch] = ((index-1)÷periodsPerOffset) + 1 
    end
  end
  offsets = protocol.offsetfields[offsetPerm, :]


  isBGFrame = measIsBGFrame(protocol.protocolMeasState)
  drivefield = read(protocol.protocolMeasState, DriveFieldBuffer)
  appliedField = read(protocol.protocolMeasState, TxDAQControllerBuffer)
  temperature = read(protocol.protocolMeasState, TemperatureBuffer)


  filename = nothing
  
  periodsPerOffset = 1
  # All periods in one frame (should) have same offset
  offsets = reshape(offsets, periodsPerOffset, :, size(offsets, 2))[1, :, :]
  offsets = reshape(offsets, protocol.calibsize..., :) # make calib size "visible" to storing function
  
  filename = saveasMDF(store, scanner, sequence, data, offsets, isBGFrame, mdf, storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, drivefield = drivefield, temperatures = temperature, applied = appliedField)
  
  @info "The measurement was saved at `$filename`."
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::MPSSystemMatrixProtocol) = Interactive()
protocolMDFStudyUse(protocol::MPSSystemMatrixProtocol) = UsingMDFStudy()

sequence(protocol::MPSSystemMatrixProtocol) = protocol.sequence