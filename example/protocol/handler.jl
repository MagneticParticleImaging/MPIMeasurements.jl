using GLMakie, Observables
using MPIMeasurements, MPIFiles
using Dates, Logging

include("makie_gui.jl")

abstract type AbstractStorageRequestHandler end
mutable struct ProtocolScriptHandler{P <: Protocol, S <: MPIScanner, L <: Base.AbstractLogger}
  const protocol::P
  const scanner::S
  const interval::Float64
  const lock::ReentrantLock
  const storage::AbstractStorageRequestHandler
  gui::SimpleProtocolGUI
  logger::L
  state::MPIMeasurements.ProtocolState
  channel::Union{BidirectionalChannel, Nothing}
  timer::Union{Timer, Nothing}
  paused::Bool
end
function setButtonCallbacks(handler::ProtocolScriptHandler)
  # Set up button callbacks
  on(handler.gui.button_row[1].clicks) do n
    tryinit(handler)
  end

  on(handler.gui.button_row[2].clicks) do n
    tryexecute(handler)
  end

  on(handler.gui.button_row[3].clicks) do n
    trypause(handler)
  end
  
  on(handler.gui.button_row[4].clicks) do n
    trycancel(handler)
  end
end
function ProtocolScriptHandler(protocol::Protocol, scanner::MPIScanner; interval = 0.01, storage = NoStorageRequestHandler(), logpath = logpath, loglevel = loglevel, loglines = loglines)
  lock = ReentrantLock()

  # Create GUI
  gui = SimpleProtocolGUI(name(protocol), name(scanner))
  
  # Create logger
  logger = SimpleProtocolGUIScriptLogger(gui; loglevel, logpath)

  handler = ProtocolScriptHandler(protocol, scanner, interval, lock, storage, gui, logger, PS_UNDEFINED, nothing, nothing, false)

  setButtonCallbacks(handler)

  return handler
end
ProtocolScriptHandler(protocol::String, scanner::String; kwargs...) = ProtocolScriptHandler(protocol, MPIScanner(scanner); kwargs...)
ProtocolScriptHandler(protocol::String, scanner::MPIScanner; kwargs...) = ProtocolScriptHandler(Protocol(protocol, scanner), scanner; kwargs...)
Base.lock(handler::ProtocolScriptHandler) = lock(handler.lock)
Base.lock(f::Base.Callable, handler::ProtocolScriptHandler) = lock(f, handler.lock)
Base.unlock(handler::ProtocolScriptHandler) = unlock(handler.lock)


function show_gui(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    with_logger(handler.logger) do
      show_gui!(handler.gui)
    end
  end
  return nothing
end

function close_gui(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    close_gui!(handler.gui)
  end
  return nothing
end
# Display functions
function updateState(handler::ProtocolScriptHandler, state::MPIMeasurements.ProtocolState)
  handler.state = state
  displayState(handler)
end 
displayState(handler::ProtocolScriptHandler) = update_state!(handler.gui, string(handler.state))


# Button Callbacks
function tryinit(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    with_logger(handler.logger) do
      try
      handler.channel = MPIMeasurements.init(handler.protocol)
      @info "Initialized protocol"
      updateState(handler, PS_INIT)
      catch e
        @error e
      end
    end
  end
end
function tryexecute(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    with_logger(handler.logger) do
      try
        handler.channel = MPIMeasurements.execute(handler.scanner, handler.protocol)
        put!(handler.channel, ProgressQueryEvent())
        handler.timer = Timer(timer -> handle(handler, timer), 0.0, interval = handler.interval)
        @info "Executing protocol"
        updateState(handler, PS_RUNNING)
      catch e
        @error e
      end
    end
  end
end
function trypause(handler::ProtocolScriptHandler)
  if !isnothing(handler.channel)
    if !handler.paused
      put!(handler.channel, PauseEvent())
    else
      put!(handler.channel, ResumeEvent())
    end
  else
    @warn "Cannot pause/resume: Protocol not running"
  end
end
function trycancel(handler::ProtocolScriptHandler)
  if !isnothing(handler.channel)
    put!(handler.channel, CancelEvent())
  else
    @warn "Cannot cancel: Protocol not running"
  end
end


function handle(handler::ProtocolScriptHandler, timer::Timer)
  lock(handler) do
    # Update State
    channel = handler.channel
    if isnothing(channel)
      return
    end
    finished = false

    if isready(channel)
      event = take!(channel)
      finished = handle(handler, handler.protocol, event)
    elseif !isopen(channel)
      finished = true
    end

    if finished
      close(timer)
      handler.channel = nothing
      handler.timer = nothing
      updateState(handler, PS_FINISHED) 
    end
  end
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ProgressEvent)
  update_progress!(handler.gui, "$(event.done)/$(event.total) $(event.unit)")
  if isopen(handler.channel) && handler.state == PS_RUNNING
    put!(handler.channel, ProgressQueryEvent())
  end
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
  updateState(handler, PS_FAILED)
  return true
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ExceptionEvent)
  currExceptions = current_exceptions(protocol.executeTask)
  @error "Protocol exception" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
  println(currExceptions)
  for i in 1:length(currExceptions) - 1
    stack = currExceptions[i]
    @error stack[:exception] trace = stacktrace(stack[:backtrace])
  end
  updateState(handler, PS_FAILED)
  return true
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::DecisionEvent)
  @debug "Handling user input event $(typeof(event))"
  choices = ["No", "Yes"]
  handleQuestion(handler, protocol, event.message, choices, (choice) -> put!(handler.channel, AnswerEvent(choice == 2, event)))
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::MultipleChoiceEvent)
  @debug "Handling user input event $(typeof(event))"
  handleQuestion(handler, protocol, event.message, event.choices, (choice) -> put!(handler.channel, ChoiceAnswerEvent(choice, event)))
  return false
end

function handleQuestion(handler::ProtocolScriptHandler, ::Protocol, message, choices, cb)
  show_decision_dialog!(handler.gui, message, string.(choices), cb, () -> setButtonCallbacks(handler))
end

# Operations
function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationSuccessfulEvent)
  @debug "Handling succesful operation $(typeof(event.operation))"
  return handleSuccessfulOperation(handler, protocol, event.operation)
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationNotSupportedEvent)
  @debug "Handling unsupported operation $(typeof(event.operation))"
  return handleUnsupportedOperation(handler, protocol, event.operation)
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationUnsuccessfulEvent)
  @debug "Handling unsuccessful operation $(typeof(event.operation))"
  return handleUnsuccessfulOperation(handler, protocol, event.operation)
end

# Pause
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol stopped"
  handler.state = PS_PAUSED
  handler.paused = true
  return false
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol can not be stopped"
  handler.paused = false
  return false
end

function handleUnsuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol failed to be stopped"
  handler.paused = false
  return false
end


# Resume
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol resumed"
  handler.state = PS_RUNNING
  handler.paused = false
  put!(handler.channel, ProgressQueryEvent()) # Restart "Main" loop
  return false
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol can not be resumed"
  handler.paused = true
  return false
end

function handleUnsuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol failed to be resumed"
  handler.paused = true
  return false
end

# Cancel
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::CancelEvent)
  @info "Protocol cancelled"
  handler.state = PS_FAILED
  return true
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::CancelEvent)
  @warn "Protocol can not be cancelled"
  return false
end
function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::StopEvent)
  @warn "Protocol can not be stopped"
  return false
end

function handleUnsuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::CancelEvent)
  @warn "Protocol failed to be cancelled"
  return false
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
  if !isnothing(handler.channel) && isopen(handler.channel)
    put!(handler.channel, FinishedAckEvent())
  else
    @warn "Storage success event received, no channel is open"
  end
  return true
end