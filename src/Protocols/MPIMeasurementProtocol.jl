export MPIMeasurementProtocol, MPIMeasurementProtocolParams, sequenceName, sequence, mdf, prepareMDF

Base.@kwdef struct MPIMeasurementProtocolParams <: ProtocolParams
  sequenceName::AbstractString
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MPIMeasurementProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  
  sequence::Union{Sequence, Nothing} = nothing
  mdf::Union{MDFv2InMemory, Nothing} = nothing
  filename::AbstractString = ""
  done::Bool = false
  cancelled::Bool = false
end

sequenceName(protocol::MPIMeasurementProtocol) = protocol.params.sequenceName
sequence(protocol::MPIMeasurementProtocol) = protocol.sequence
mdf(protocol::MPIMeasurementProtocol) = protocol.mdf

#TODO: This has currently no link to an MDF store. How should we integrate it?
function prepareMDF(protocol::MPIMeasurementProtocol, filename::AbstractString, study::MDFv2Study, experiment::MDFv2Experiment, operator::AbstractString="anonymous")
  protocol.mdf = MDFv2InMemory()
  protocol.mdf.root = defaultMDFv2Root()
  protocol.mdf.study = study
  protocol.mdf.experiment = experiment
  protocol.mdf.scanner = MDFv2Scanner(
    boreSize = ustrip(u"m", scannerBoreSize(protocol.scanner)),
    facility = scannerFacility(protocol.scanner),
    manufacturer = scannerManufacturer(protocol.scanner),
    name = scannerName(protocol.scanner),
    operator = operator,
    topology = scannerTopology(protocol.scanner)
  )

  protocol.filename = filename
end

function init(protocol::MPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  configDir_ = configDir(scanner_)
  sequenceName_ = sequenceName(protocol)
  filename = joinpath(configDir_, "Sequences", "$sequenceName_.toml")
  protocol.sequence = Sequence(filename)
  return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function execute(protocol::MPIMeasurementProtocol)
  scanner_ = scanner(protocol)

  handleEvents(protocol)
  if protocol.cancelled
    close(protocol.biChannel)
    return
  end
  
  if !isnothing(protocol.sequence)
    uMeas = measurement(protocol)
    protocol.done = true
  end

  handleEvents(protocol)
  if protocol.cancelled
    close(protocol.biChannel)
    return
  end

  #if !isnothing(protocol.mdf)
  @info "Asking now"
  if askConfirmation(protocol, "Would you like to save the measurement result?")
    @info "Sequence finished. Now saving to MDF."
    #fillMDF(seqCont, protocol.mdf)
    #saveasMDF(protocol.filename, protocol.mdf)
    @info "Would save now"
  else
    @warn "No MDF defined and thus, no data is saved. If this is a mistake "*
          "please run `prepareMDF` prior to calling `runProtocol`."
  end
  handleEvents(protocol)
  @info "Protocol finished."
  close(protocol.biChannel)
end

function measurement(protocol::MPIMeasurementProtocol)
  scanner = protocol.scanner
  scanner.currentSequence = protocol.sequence
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


