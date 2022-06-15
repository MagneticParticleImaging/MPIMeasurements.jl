export ContinousMeasurementProtocol, ContinousMeasurementProtocolParams
"""
Parameters for the MPIMeasurementProtocol
"""
Base.@kwdef mutable struct ContinousMeasurementProtocolParams <: ProtocolParams
  "Pause between measurements"
  pause::typeof(1.0u"s") = 0.2u"s"
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
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
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::ContinousMeasurementProtocolParams
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  executeTask::Union{Task, Nothing} = nothing

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing


  latestMeas::Array{Float32, 4} = zeros(Float32, 0, 0, 0, 0)
  stopped::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
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
    controllers = getDevices(protocol.scanner, TxDAQController)
    if length(controllers) > 1
      throw(IllegalStateException("Cannot unambiguously find a TxDAQController as the scanner has $(length(controllers)) of them"))
    end
    protocol.txCont = controllers[1]
    protocol.txCont.currTx = nothing
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


  while true
    @info "Taking new measurement"
    measurement(protocol)
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
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
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
    @error "Producer failed"
    currExceptions = current_exceptions(producer)
    for stack in currExceptions
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
  end
  if Base.istaskfailed(consumer)
    @error "Consumer failed"
    currExceptions = current_exceptions(producer)
    for stack in currExceptions
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    if isnothing(ex)
      ex = currExceptions[1][:exception]
    end
  end
  if !isnothing(ex)
    throw(ErrorException("Measurement failed, see logged exceptions and stacktraces"))
  end

  protocol.latestMeas = copy(measState.buffer)
end

function asyncMeasurement(protocol::ContinousMeasurementProtocol)
  scanner = protocol.scanner
  sequence = protocol.params.sequence
  prepareAsyncMeasurement(scanner, sequence)
  if protocol.params.controlTx
    controlTx(protocol.txCont, sequence, protocol.txCont.currTx)
  end
  protocol.seqMeasState.producer = @tspawnat scanner.generalParams.producerThreadID asyncProducer(protocol.seqMeasState.channel, scanner, sequence, prepTx = !protocol.params.controlTx)
  bind(protocol.seqMeasState.channel, protocol.seqMeasState.producer)
  protocol.seqMeasState.consumer = @tspawnat scanner.generalParams.consumerThreadID asyncConsumer(protocol.seqMeasState.channel, scanner)
  return protocol.seqMeasState
end


function cleanup(protocol::ContinousMeasurementProtocol)
  # NOP
end

function stop(protocol::ContinousMeasurementProtocol)
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
  data = protocol.latestMeas
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end


function handleEvent(protocol::ContinousMeasurementProtocol, event::ProgressQueryEvent)
  reply = ProgressEvent(protocol.counter, 0, "Measurements", event)  
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::ContinousMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

