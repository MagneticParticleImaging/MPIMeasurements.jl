using Term, Term.LiveWidgets
using REPL, REPL.TerminalMenus
using MPIMeasurements, MPIFiles

abstract type AbstractStorageRequestHandler end
mutable struct ProtocolScriptHandler{P <: Protocol, S <: MPIScanner, L <: Base.AbstractLogger}
  const protocol::P
  const scanner::S
  const interval::Float64
  const lock::ReentrantLock
  const storage::AbstractStorageRequestHandler
  appTask::Union{Nothing, Task}
  widgets::Dict
  layout::Expr
  transitions::Dict
  logger::L
  state::MPIMeasurements.ProtocolState
  channel::Union{BidirectionalChannel, Nothing}
  timer::Union{Timer, Nothing}
end
function ProtocolScriptHandler(protocol::Protocol, scanner::MPIScanner; interval = 0.01, storage = NoStorageRequestHandler(), logpath = logpath)
  lock = ReentrantLock()

  layout = :(
    ( (header(3, 0.33) * state(3, 0.33) * progress(3, 0.33)) / 
      info(20, 1.0) / 
      (init(3, 0.25) * execute(3, 0.25) * pause(3, 0.25) * cancel(3, 0.25))
    )
  )

  widgets = Dict(
    :header => TextWidget(name(protocol); title = name(scanner), as_panel = true),
    :state => TextWidget(""; title = "State", as_panel = true),
    :progress => TextWidget(""; title = "Progress", as_panel = true),
    # Override pager controls s.t. Up and Down Keys function correctly
    :info => ProtocolInformationWidget(; title = "Info"),
    :init => Button("Init"),
    :execute => ToggleButton("Execute"),
    :pause => ToggleButton("Pause"),
    :cancel => Button("Cancel"),
  )

  # Set transition rules
  upDict = Dict(
    :init => :info,
    :execute => :info,
    :pause => :info,
    :cancel => :info,
    :info => :header,
  )
  downDict = Dict(
    :info => :init,
    :header => :info,
    :state => :info,
    :progress => :info
  )
  rightDict = Dict(
    :header => :state,
    :state => :progress,
    :init => :execute,
    :execute => :pause,
    :pause => :cancel
  )
  leftDict = Dict(
    :progress => :state,
    :state => :header,
    :cancel => :pause,
    :pause => :execute,
    :execute => :init
  )
  transitions = Dict(
    ArrowUp() => upDict,
    ArrowDown() => downDict,
    ArrowLeft() => leftDict,
    ArrowRight() => rightDict,
  )

  logger = ProtocolScriptLogger(widgets[:info], logpath)


  handler =  ProtocolScriptHandler(protocol, scanner, interval, lock, storage, nothing, widgets, layout, transitions, logger, PS_UNDEFINED, nothing, nothing)

  # Callbacks
  widgets[:init].callback = (btn) -> tryinit(handler)
  widgets[:execute].callback = (btn) -> tryexecute(handler)
  widgets[:pause].callback = (btn) -> trypause(handler)
  widgets[:cancel].callback = (btn) -> trycancel(handler)

  return handler
end
ProtocolScriptHandler(protocol::String, scanner::String; kwargs...) = ProtocolScriptHandler(protocol, MPIScanner(scanner); kwargs...)
ProtocolScriptHandler(protocol::String, scanner::MPIScanner; kwargs...) = ProtocolScriptHandler(Protocol(protocol, scanner), scanner; kwargs...)
Base.lock(handler::ProtocolScriptHandler) = lock(handler.lock)
Base.lock(f::Base.Callable, handler::ProtocolScriptHandler) = lock(f, handler.lock)
Base.unlock(handler::ProtocolScriptHandler) = unlock(handler.lock)


function Term.play(handler::ProtocolScriptHandler; transient = true)
  lock(handler.lock) do
    with_logger(handler.logger) do
      if isnothing(handler.appTask) || istaskdone(handler.appTask)
        app = App(handler.layout; widgets = handler.widgets, expand = true, transition_rules = handler.transitions)
        handler.appTask = Threads.@spawn :interactive begin
          println("Starting Term App")
          play(app, transient = transient)
          println("Exiting Term App. Repl is now usable")
        end
      end
    end
  end
  return nothing
end
# Display functions
function updateState(handler::ProtocolScriptHandler, state::MPIMeasurements.ProtocolState)
  handler.state = state
  displayState(handler)
end 
displayState(handler::ProtocolScriptHandler) = handler.widgets[:state].text = string(handler.state)


# Button Callbacks
function tryinit(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    with_logger(handler.logger) do
      try
      handler.channel = MPIMeasurements.init(handler.protocol)
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
      updateState(handler, PS_RUNNING)
      catch e
        @error e
      end
    end
  end
end
function trypause(handler::ProtocolScriptHandler)
  error("Not implemented")
  displayState(handler)
end
function trycancel(handler::ProtocolScriptHandler)
  error("Not implemented")
  displayState(handler)
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
  handler.widgets[:progress].text = "$(event.done)/$(event.total) $(event.unit)"
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
  for i in 1:length(currExceptions) - 1
    stack = currExceptions[i]
    @error stack[:exception] trace = stacktrace(stack[:backtrace])
  end
  updateState(handler, PS_FAILED)
  return true
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::DecisionEvent)
  choices = ["No", "Yes"]
  handleQuestion(handler, protocol, event.message, choices, (choice) -> put!(handler.channel, AnswerEvent(choice == 2, event)))
  return false
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::MultipleChoiceEvent)
  handleQuestion(handler, protocol, event.message, event.choices, (choice) -> put!(handler.channel, ChoiceAnswerEvent(choice, event)))
  return false
end

function handleQuestion(handler::ProtocolScriptHandler, ::Protocol, message, choices, cb)
  @info "Test log"
  askQuestion(handler.widgets[:info], message, string.(choices), cb)
end

# Operations
function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationSuccessfulEvent)
  return handleSuccessfulOperation(handler, protocol, event.operation)
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationNotSupportedEvent)
  return handleUnsupportedOperation(handler, protocol, event.operation)
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::OperationUnsuccessfulEvent)
  return handleUnsuccessfulOperation(handler, protocol, event.operation)
end

# Pause
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol stopped"
  handler.state = PS_PAUSED
  # TODO UI 
  return false
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol can not be stopped"
  # TODO UI
  return false
end

function handleUnsuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::PauseEvent)
  @info "Protocol failed to be stopped"
  # TODO UI
  return false
end


# Resume
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol resumed"
  handler.state = PS_RUNNING
  # TODO UI
  put!(handler.channel, ProgressQueryEvent()) # Restart "Main" loop
  return false
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol can not be resumed"
  # TODO UI
  return false
end

function handleUnsuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol failed to be resumed"
  # TODO UI
  return false
end

# Cancelt
function handleSuccessfulOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::CancelEvent)
  @info "Protocol cancelled"
  handler.state = PS_FAILED
  return true
end

function handleUnsupportedOperation(handler::ProtocolScriptHandler, protocol::Protocol, event::CancelEvent)
  @warn "Protocol can not be cancelled"
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
  put!(handler.channel, FinishedAckEvent())
  return true
end