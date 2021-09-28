export  Protocol, ProtocolParams, name, description, scanner, params, runProtocol,
        init, execute, cleanup, ProtocolEvent, InfoQueryEvent,
        InfoEvent, DecisionEvent, AnswerEvent, StopEvent, ResumeEvent, CancelEvent, ProgressQueryEvent,
        ProgressEvent, UndefinedEvent, DataQueryEvent, DataAnswerEvent, FinishedNotificationEvent, FinishedAckEvent,
        ExceptionEvent, IllegaleStateEvent

abstract type ProtocolParams end

name(protocol::Protocol)::AbstractString = protocol.name
description(protocol::Protocol)::AbstractString = protocol.description
scanner(protocol::Protocol)::MPIScanner = protocol.scanner
params(protocol::Protocol)::ProtocolParams = protocol.params
biChannel(protocol::Protocol) = protocol.biChannel

"General constructor for all concrete subtypes of Protocol."
function Protocol(protocolDict::Dict{String, Any}, scanner::MPIScanner)
  if haskey(protocolDict, "name")
    name = pop!(protocolDict, "name")
  else 
    throw(ProtocolConfigurationError("There is no protocol name given in the configuration."))
  end

  if haskey(protocolDict, "description")
    description = pop!(protocolDict, "description")
  else 
    throw(ProtocolConfigurationError("There is no protocol description given in the configuration."))
  end

  if haskey(protocolDict, "targetScanner")
    targetScanner = pop!(protocolDict, "targetScanner")
    if targetScanner != scannerName(scanner)
      throw(ProtocolConfigurationError("The target scanner (`$targetScanner`) for the protocol does not match the given scanner (`$(scannerName(scanner))`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no target scanner for the protocol given in the configuration."))
  end

  if haskey(protocolDict, "type")
    protocolType = pop!(protocolDict, "type")
  else 
    throw(ProtocolConfigurationError("There is no protocol type given in the configuration."))
  end 

  paramsType = getConcreteType(ProtocolParams, protocolType*"Params")
  params = paramsType(protocolDict)
  ProtocolImpl = getConcreteType(Protocol, protocolType)

  biChannel = BidirectionalChannel{ProtocolEvent}(32)

  return ProtocolImpl(name=name, description=description, scanner=scanner, biChannel = biChannel, params=params)
end

function Protocol(protocolName::AbstractString, scanner::MPIScanner)
  configDir_ = configDir(scanner)
  filename = joinpath(configDir_, "Protocols", "$protocolName.toml")

  if isfile(filename)
    protocolDict = TOML.parsefile(filename)
  else
    throw(ProtocolConfigurationError("Could not find a valid configuration for protocol with name `$protocolName` and the derived path `$filename`."))
  end

  if haskey(protocolDict, "name")
    name = protocolDict["name"]
    if name != protocolName
      throw(ProtocolConfigurationError("The protocol name given in the configuration (`$name`) does not match the name derived from the filename (``$protocolName`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no protocol name given in the configuration."))
  end

  return Protocol(protocolDict, scanner)
end

Protocol(protocolName::AbstractString, scannerName::AbstractString) = Protocol(protocolName, MPIScanner(scannerName))
Protocol(protocolDict::Dict{String, Any}, scannerName::AbstractString) = Protocol(protocolDict, MPIScanner(scannerName))

function runProtocol(protocol::Protocol)
  # TODO: Error handling
  # TODO command line "handler"
  in, out = init(protocol)
  @async begin
    execute(protocol)
    cleanup(protocol)
  end
  return in, out
end

abstract type ProtocolEvent end

@mustimplement init(protocol::Protocol)
@mustimplement _execute(protocol::Protocol)
@mustimplement cleanup(protocol::Protocol)
@mustimplement stop(protocol::Protocol)
@mustimplement resume(protocol::Protocol)
@mustimplement cancel(protocol::Protocol)

function execute(protocol::Protocol)
  protocol.executeTask = current_task()
  try
    _execute(protocol)
  catch ex
    if ex isa CancelException
      close(protocol.biChannel)
    elseif ex isa IllegalStateException
      put!(protocol.biChannel, IllegaleStateEvent(ex.message))
      close(protocol.biChannel)
    else
      # Let task fail
      put!(protocol.biChannel, ExceptionEvent(ex))
      close(protocol.biChannel)
      throw(ex)
    end
  end
end

struct UndefinedEvent <: ProtocolEvent
  event::ProtocolEvent
end
# Interaction Events, only necessary for interactive protocolts
struct DecisionEvent <: ProtocolEvent
  message::AbstractString
end
struct AnswerEvent <: ProtocolEvent
  answer::Bool
  question::DecisionEvent
end

# (Mandatory) Control flow events for all protocols
struct StopEvent <: ProtocolEvent end
struct ResumeEvent <: ProtocolEvent end
struct CancelEvent <: ProtocolEvent end
struct OperationNotSupportedEvent <: ProtocolEvent end
struct IllegaleStateEvent <: ProtocolEvent
  message::AbstractString
end
struct ExceptionEvent <: ProtocolEvent 
  exception::Exception
end
struct FinishedNotificationEvent <: ProtocolEvent end
struct FinishedAckEvent <: ProtocolEvent end
#Maybe a status (+ query) event and all Protocols have the states: UNKNOWN, INIT, EXECUTING, PAUSED, FINISHED

# Display/Information Events
struct InfoQueryEvent <: ProtocolEvent
  message::AbstractString # for example "TEMP" could return a value from temp sensor if it exists, protocol specific
end
struct InfoEvent <: ProtocolEvent
  message::AbstractString
  query::InfoQueryEvent
end
struct ProgressQueryEvent <: ProtocolEvent end
struct ProgressEvent <: ProtocolEvent
  done::Int
  total::Int
  unit::AbstractString
  query::ProgressQueryEvent
end
struct DataQueryEvent <: ProtocolEvent
  message::AbstractString
end
struct DataAnswerEvent <: ProtocolEvent
  data::Any
  query::DataQueryEvent
end
struct UnknownDataQueryEvent <: ProtocolEvent
  query::DataQueryEvent
end

function askConfirmation(protocol::Protocol, message::AbstractString)
  channel = biChannel(protocol)
  question = DecisionEvent(message)
  put!(channel, question)
  while isopen(channel) || isready(channel)
    event = take!(channel)
    # Note that for immutable objects the '==' does not guarantee that the reply is to the actual current question
    if event isa AnswerEvent && event.question == question 
      return event.answer
    else 
      handleEvent(protocol, event)
    end
    sleep(0.001)
  end
end

handleEvent(protocol::Protocol, event::StopEvent) = stop(protocol)
handleEvent(protocol::Protocol, event::ResumeEvent) = resume(protocol) 
handleEvent(protocol::Protocol, event::CancelEvent) = cancel(protocol)
handleEvent(protocol::Protocol, event::ProtocolEvent) = put!(biChannel(protocol), UndefinedEvent(event))
#handleEvent(protocol::Protocol, event::InfoQueryEvent) = 

function handleEvents(protocol::Protocol)
  while isready(protocol.biChannel)
    event = take!(protocol.biChannel)
    handleEvent(protocol, event)
  end
end

include("DAQMeasurementProtocol.jl")
include("MPIMeasurementProtocol.jl")
include("RobotBasedProtocol.jl")
include("RobotBasedSystemMatrixProtocol.jl")
include("AsyncMeasurementProtocol.jl")
#include("TransferFunctionProtocol.jl")