export ContinousMeasurementProtocol, ContinousMeasurementProtocolParams
"""
Parameters for the `ContinousMeasurementProtocol``

$FIELDS
"""
Base.@kwdef mutable struct ContinousMeasurementProtocolParams <: ProtocolParams
  "Foreground frames to measure. Overwrites sequence frames"
  fgFrames::Int64 = 1
  "Background frames to measure. Overwrites sequence frames"
  bgFrames::Int64 = 1
  "Pause between measurements"
  pause::typeof(1.0u"s") = 0.2u"s"
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If unset no background measurement will be taken"
  measureBackground::Bool = true
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
end
function ContinousMeasurementProtocolParams(dict::Dict, scanner::MPIScanner) 
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(ContinousMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end
ContinousMeasurementProtocolParams(dict::Dict) = params_from_dict(ContinousMeasurementProtocolParams, dict)

Base.@kwdef mutable struct ContinousMeasurementProtocol <: Protocol
  @add_protocol_fields ContinousMeasurementProtocolParams

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing


  latestMeas::Array{Float32, 4} = zeros(Float32, 0, 0, 0, 0)
  latestBgMeas::Array{Float32, 4} = zeros(Float32, 0, 0, 0, 0)
  stopped::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
  counter::Int64 = 0
end

function requiredDevices(protocol::ContinousMeasurementProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::ContinousMeasurementProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  protocol.counter = 0

  return nothing
end

function timeEstimate(protocol::ContinousMeasurementProtocol)
  est = "∞"
  return est
end

function enterExecute(protocol::ContinousMeasurementProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
end


function _execute(protocol::ContinousMeasurementProtocol)
  @info "Measurement protocol started"

  if protocol.params.measureBackground
    if askChoices(protocol, "Press continue when background measurement can be taken", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
    acqNumFrames(protocol.params.sequence, protocol.params.bgFrames)

    @debug "Taking background measurement."
    protocol.unit = "BG Measurement"
    protocol.latestBgMeas = measurement(protocol)
    if askChoices(protocol, "Press continue when foreground loop can be started", ["Cancel", "Continue"]) == 1
      throw(CancelException())
    end
  end

  protocol.unit = "Measurements"
  while true
    @info "Taking new measurement"
    protocol.latestMeas = measurement(protocol)
    protocol.counter+=1

    measPauseOver = false
    waitTimer = Timer(ustrip(u"s", protocol.params.pause))
    @async begin
      wait(waitTimer)
      measPauseOver = true
    end

    notifiedStop = false
    while !measPauseOver || protocol.stopped
      handleEvents(protocol)
      if !notifiedStop && protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(PauseEvent()))
        notifiedStop = true
      end
      if notifiedStop && !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
        notifiedStop = false
      end
      protocol.cancelled && throw(CancelException())
      sleep(0.05)
    end
    close(waitTimer)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function measurement(protocol::ContinousMeasurementProtocol)
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

  return copy(read(sink(protocol.seqMeasState.sequenceBuffer, MeasurementBuffer)))
end

function asyncMeasurement(protocol::ContinousMeasurementProtocol)
  scanner_ = protocol.scanner
  sequence = protocol.params.sequence
  daq = getDAQ(scanner_)
  if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
  end
  setup(daq, sequence)
  protocol.seqMeasState = SequenceMeasState(daq, sequence)
  protocol.seqMeasState.producer = @tspawnat scanner_.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, protocol, sequence)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner_.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState)
  return protocol.seqMeasState
end

function pause(protocol::ContinousMeasurementProtocol)
  protocol.stopped = true
end

function resume(protocol::ContinousMeasurementProtocol)
  protocol.stopped = false
end

function cancel(protocol::ContinousMeasurementProtocol)
  protocol.cancelled = true
  #put!(protocol.biChannel, OperationNotSupportedEvent(CancelEvent()))
  # TODO stopTx and reconnect for pipeline and so on
end

function handleEvent(protocol::ContinousMeasurementProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "FG"
    if length(protocol.latestMeas) > 0
      data = copy(protocol.latestMeas)
    else
      data = nothing
    end
  elseif event.message == "BG"
    if length(protocol.latestBgMeas) > 0
      data = copy(protocol.latestBgMeas)
    else
      data = nothing
    end
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
    return
  end
  mdf = prepareAsMDF(data, protocol.scanner, protocol.params.sequence)
  put!(protocol.biChannel, DataAnswerEvent(mdf, event))
end


function handleEvent(protocol::ContinousMeasurementProtocol, event::ProgressQueryEvent)
  reply = ProgressEvent(protocol.counter, 0, protocol.unit, event)  
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::ContinousMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

