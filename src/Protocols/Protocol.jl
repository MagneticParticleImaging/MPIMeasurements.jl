export  Protocol, ProtocolParams, name, description, scanner, params, runProtocol,
        init, execute, cleanup, timeEstimate, ProtocolEvent, InfoQueryEvent,
        InfoEvent, DecisionEvent, AnswerEvent, StopEvent, ResumeEvent, CancelEvent, RestartEvent, ProgressQueryEvent,
        ProgressEvent, UndefinedEvent, DataQueryEvent, DataAnswerEvent, FinishedNotificationEvent, FinishedAckEvent,
        ExceptionEvent, IllegaleStateEvent, DatasetStoreStorageRequestEvent, StorageSuccessEvent, StorageRequestEvent,
        OperationSuccessfulEvent, OperationUnsuccessfulEvent, OperationNotSupportedEvent, MultipleChoiceEvent, ChoiceAnswerEvent


abstract type ProtocolParams end

export ProtocolState, PS_UNDEFINED, PS_INIT, PS_RUNNING, PS_PAUSED, PS_FINISHED, PS_FAILED
@enum ProtocolState PS_UNDEFINED PS_INIT PS_RUNNING PS_PAUSED PS_FINISHED PS_FAILED

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
  params = paramsType(protocolDict, scanner)
  ProtocolImpl = getConcreteType(Protocol, protocolType)

  return ProtocolImpl(name=name, description=description, scanner=scanner, params=params)
end

function Protocol(protocolName::AbstractString, scanner::MPIScanner)
  configDir_ = configDir(scanner)
  filename = joinpath(configDir_, "Protocols", "$protocolName.toml")

  if isfile(filename)
    protocolDict = TOML.parsefile(filename)
  else
    throw(ProtocolConfigurationError("Could not find a valid configuration for protocol with name `$protocolName` and the derived path `$filename`."))
  end

  protocolDict["name"] = protocolName

  return Protocol(protocolDict, scanner)
end

Protocol(protocolName::AbstractString, scannerName::AbstractString) = Protocol(protocolName, MPIScanner(scannerName))
Protocol(protocolDict::Dict{String, Any}, scannerName::AbstractString) = Protocol(protocolDict, MPIScanner(scannerName))

# TODO (from Jonas): Is this still used?
function runProtocol(protocol::Protocol)
  # TODO: Error handling
  # TODO command line "handler"
  channel = init(protocol)
  @async begin
    execute(protocol)
    cleanup(protocol)
  end
  return channel
end

abstract type ProtocolEvent end

@mustimplement _init(protocol::Protocol) # Prepare necessary data structures, ex. buffer for samples + background meas
@mustimplement _execute(protocol::Protocol)
@mustimplement enterExecute(protocol::Protocol) # Prepare execution tracking flags, ex. execution done or cancelled flags
@mustimplement cleanup(protocol::Protocol)
@mustimplement stop(protocol::Protocol)
@mustimplement resume(protocol::Protocol)
@mustimplement cancel(protocol::Protocol)

function init(protocol::Protocol)
  @debug "Initializing protocol $(name(protocol)) with inner initializer."
  checkRequiredDevices(protocol)
  _init(protocol)
end

function checkRequiredDevices(protocol::Protocol)
  missingDevices = []
  scanner = protocol.scanner
  for device in requiredDevices(protocol)
    if length(getDevices(scanner, device)) == 0
      push!(missingDevices, device)
    end
  end
  if length(missingDevices) > 0
    message = "Protocol $(typeof(protocol)) is missing the following required devices: " * join(string.(missingDevices), ", ", " and ")
    throw(IllegalStateException(message))
  end
end

requiredDevices(protocol::Protocol) = []

timeEstimate(protocol::Protocol) = "Unknown"

function execute(protocol::Protocol, threadID::Integer = 1)
  if isnothing(protocol.executeTask) || istaskdone(protocol.executeTask)
    @debug "Executing protocol since the execute task is either `nothing` or done."
    protocol.biChannel = BidirectionalChannel{ProtocolEvent}(32)
    @tspawnat threadID executionTask(protocol)
    return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
  else
    if !isnothing(protocol.executeTask)
      @debug "The execute task is not `nothing` but not done."
    end
    @warn "Protocol cannot be executed again as it is still running."
    return nothing
  end
end

function executionTask(protocol::Protocol)
  protocol.executeTask = current_task()
  try
    enterExecute(protocol)
    _execute(protocol)
  catch ex
    if ex isa CancelException
      @debug "A CancelException has been thrown during execution."
      put!(protocol.biChannel, OperationSuccessfulEvent(CancelEvent()))
      close(protocol.biChannel)
    elseif ex isa IllegalStateException
      @debug "An IllegalStateException has been thrown during execution."
      put!(protocol.biChannel, IllegaleStateEvent(ex.message))
      close(protocol.biChannel)
    else
      # Let task fail
      @debug "An exception has been thrown during execution."
      put!(protocol.biChannel, ExceptionEvent(ex))
      close(protocol.biChannel)
      throw(ex)
    end
  end

  @debug "Execution task ending. Closing communication channel."
  close(protocol.biChannel)
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
struct MultipleChoiceEvent <: ProtocolEvent # TODO: How about multiple values for a question?
  message::AbstractString
  choices::Vector{AbstractString}
end
struct ChoiceAnswerEvent <: ProtocolEvent
  answer::Int64
  question::MultipleChoiceEvent
end

# (Mandatory) Control flow events for all protocols
struct StopEvent <: ProtocolEvent end
struct ResumeEvent <: ProtocolEvent end
struct CancelEvent <: ProtocolEvent end
struct RestartEvent <: ProtocolEvent end
struct OperationNotSupportedEvent <: ProtocolEvent
  operation::ProtocolEvent
end
struct OperationSuccessfulEvent <: ProtocolEvent
  operation::ProtocolEvent
end
struct OperationUnsuccessfulEvent <: ProtocolEvent
  operation::ProtocolEvent
end
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

abstract type StorageRequestEvent <: ProtocolEvent end
struct DatasetStoreStorageRequestEvent <: StorageRequestEvent
  datastore::DatasetStore
  params::Dict
end
struct StorageSuccessEvent <: ProtocolEvent
  filename::AbstractString
end

function askConfirmation(protocol::Protocol, message::AbstractString)
  @debug "Asking for confirmation on \"$message\"."
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

function askChoices(protocol::Protocol, message::AbstractString, choices::Vector{<:AbstractString})
  @debug "Asking for decision on \"$message\" with the following choices: $(join(choices, ", ", " and "))."
  channel = biChannel(protocol)
  question = MultipleChoiceEvent(message, choices)
  put!(channel, question)
  while isopen(channel) || isready(channel)
    event = take!(channel)
    # Note that for immutable objects the '==' does not guarantee that the reply is to the actual current question
    if event isa ChoiceAnswerEvent && event.question == question 
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

# Traits
abstract type ProtocolInteractivity end
struct NonInteractive <: ProtocolInteractivity end
struct Interactive <: ProtocolInteractivity end
@mustimplement protocolInteractivity(protocol::Protocol)

include("MPIMeasurementProtocol.jl")
include("RobotBasedProtocol.jl")
include("RobotBasedSystemMatrixProtocol.jl")
include("ContinousMeasurementProtocol.jl")
#include("TransferFunctionProtocol.jl")