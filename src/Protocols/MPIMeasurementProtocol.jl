export MPIMeasurementProtocol, MPIMeasurementProtocolParams, sequenceName, sequence, mdf, prepareMDF

Base.@kwdef struct MPIMeasurementProtocolParams <: ProtocolParams
  #sequenceName::AbstractString
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MPIMeasurementProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
end

function init(protocol::MPIMeasurementProtocol)
  return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function execute(protocol::MPIMeasurementProtocol)
  @info "Measurement protocol started"

  handleEvents(protocol)
  if protocol.cancelled
    close(protocol.biChannel)
    return
  end
  
  if !isnothing(protocol.scanner.currentSequence)
    measurement(protocol)
    protocol.done = true
  end

  handleEvents(protocol)
  if protocol.cancelled
    close(protocol.biChannel)
    return
  end


  put!(protocol.biChannel, FinishedNotificationEvent())
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    if protocol.cancelled
      close(protocol.biChannel)
      return
    end
    sleep(0.01)
  end

  @info "Protocol finished."
  close(protocol.biChannel)
end

function measurement(protocol::MPIMeasurementProtocol)
  scanner = protocol.scanner
  measState = asyncMeasurement(scanner)
  producer = measState.producer
  consumer = measState.consumer
  result = nothing

  try 
    Base.wait(producer)
  catch e 
    if !isa(e, TaskFailedException) 
      @error "Unexpected error"
      @error e
    end
  end

  try
    Base.wait(producer)
  catch e
    if !isa(e, TaskFailedException)
      @error "Unexpected error"
      @error e
    end
  end

  # Check tasks
  if Base.istaskfailed(producer)
    @error "Producer failed"
    stack = Base.catch_stack(producer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
    result = nothing
  elseif  Base.istaskfailed(consumer)
    @error "Consumer failed"
    stack = Base.catch_stack(consumer)[1]
    @error stack[1]
    @error stacktrace(stack[2])
    result = nothing
  else
    result = measState.buffer
  end
  return result
end


function cleanup(protocol::MPIMeasurementProtocol)
  # NOP
end

function stop(protocol::MPIMeasurementProtocol)
  # NOP
end

function resume(protocol::MPIMeasurementProtocol)
  # NOP
end

function cancel(protocol::MPIMeasurementProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::MPIMeasurementProtocol, event::DataQueryEvent)
  data = nothing
  if protocol.done
    data = protocol.scanner.seqMeasState.buffer
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end


function handleEvent(protocol::MPIMeasurementProtocol, event::ProgressQueryEvent)
  done = protocol.done ? 1 : 0
  put!(protocol.biChannel, ProgressQueryEvent(done, 1, event))
end

handleEvent(protocol::MPIMeasurementProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

