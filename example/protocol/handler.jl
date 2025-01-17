using REPL, REPL.TerminalMenus
using MPIMeasurements, MPIFiles

abstract type AbstractStorageRequestHandler end
mutable struct ProtocolScriptHandler{P <: Protocol, S <: MPIScanner, L <: Base.AbstractLogger}
  const protocol::P
  const scanner::S
  const interval::Float64
  const lock::ReentrantLock
  const storage::AbstractStorageRequestHandler
  logger::L
  channel::Union{BidirectionalChannel, Nothing}
  timer::Union{Timer, Nothing}
end
function ProtocolScriptHandler(protocol::Protocol, scanner::MPIScanner; interval = 0.01, storage = NoStorageRequestHandler(), logpath = logpath)
  lock = ReentrantLock()
  logger = ProtocolScriptLogger(logpath)
  return ProtocolScriptHandler(protocol, scanner, interval, lock, storage, logger, nothing, nothing)
end
ProtocolScriptHandler(protocol::String, scanner::String; kwargs...) = ProtocolScriptHandler(protocol, MPIScanner(scanner); kwargs...)
ProtocolScriptHandler(protocol::String, scanner::MPIScanner; kwargs...) = ProtocolScriptHandler(Protocol(protocol, scanner), scanner; kwargs...)
Base.lock(handler::ProtocolScriptHandler) = lock(handler.lock)
Base.lock(f::Base.Callable, handler::ProtocolScriptHandler) = lock(f, handler.lock)
Base.unlock(handler::ProtocolScriptHandler) = unlock(handler.lock)

function MPIMeasurements.execute(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    if isnothing(handler.channel)
      with_logger(handler.logger) do 
        MPIMeasurements.init(handler.protocol)
        handler.channel = MPIMeasurements.execute(handler.scanner, handler.protocol)
        put!(handler.channel, ProgressQueryEvent())
        handler.timer = Timer(timer -> handle(handler, timer), 0.0, interval = handler.interval)
      end
    else
      error("Channel to protocol is already open")
    end
  end
end


function handle(handler::ProtocolScriptHandler, timer::Timer)
  lock(handler) do 
    channel = handler.channel
    finished = isnothing(channel)

    if isready(channel)
      event = take!(channel)
      @debug "Script event handler received event of type $(typeof(event)) and is now dispatching it."
      finished = handle(handler, handler.protocol, event)
      @debug "Handled event of type $(typeof(event))."
    end

    if finished
      close(timer)
      handler.channel = nothing
      handler.timer = nothing
    end
  end
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ProgressEvent)
  print("$(event.done)/$(event.total) $(event.unit)\r")
  put!(handler.channel, ProgressQueryEvent())
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::UndefinedEvent)
  @warn "Protocol $(typeof(protocol)) send undefined event in response to $(typeof(event.event))"
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ProtocolEvent)
  @warn "No handler defined for event $(typeof(event)) and protocol $(typeof(protocol))"
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::IllegaleStateEvent)
  @error event.message
  return true
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ExceptionEvent)
  currExceptions = current_exceptions(protocol.executeTask)
  @error "Protocol exception" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
  for i in 1:length(currExceptions) - 1
    stack = currExceptions[i]
    @error stack[:exception] trace = stacktrace(stack[:backtrace])
  end
  return true
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::DecisionEvent)
  choices = ["No", "Yes"]
  choice = handleQuestion(handler, protocol, event.message, choices)
  put!(handler.channel, AnswerEvent(choice == 2, event))
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::MultipleChoiceEvent)
  choice = handleQuestion(handler, protocol, event.message, event.choices)
  put!(handler.channel, ChoiceAnswerEvent(choice, event))
  return false
end

function handleQuestion(handler::ProtocolScriptHandler, ::Protocol, message, choices)
  println()
  menu = RadioMenu(string.(choices))
  if handler.logger isa ProtocolScriptLogger
    disable(handler.logger)
  end
  choice = request(message, menu)
  if handler.logger isa ProtocolScriptLogger
    enable(handler.logger)
  end
  return choice
end


handle(handler::ProtocolScriptHandler, protocol::Protocol, event::FinishedNotificationEvent) = handler.storage(handler)
struct NoStorageRequestHandler <: AbstractStorageRequestHandler end
function (::NoStorageRequestHandler)(handler::ProtocolScriptHandler)
  put!(handler.channel, FinishedAckEvent())
  return true
end

struct FileStorageRequestHandler <: AbstractStorageRequestHandler
  filepath::String
end
function (storage::FileStorageRequestHandler)(handler::ProtocolScriptHandler)
  put!(handler.channel, FileStorageRequestEvent(proto.filepath))
  return false
end

struct DatasetStoreStorageRequestHandler <: AbstractStorageRequestHandler
  store::MDFDatasetStore
  mdf::MDFv2InMemory
end
function (storage::DatasetStoreStorageRequestHandler)(handler::ProtocolScriptHandler)
  put!(handler.channel, DatasetStoreStorageRequestEvent(storage.store, storage.mdf))
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::StorageSuccessEvent)
  put!(handler.channel, FinishedAckEvent())
  return true
end