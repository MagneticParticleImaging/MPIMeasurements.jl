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


  handler =  ProtocolScriptHandler(protocol, scanner, interval, lock, storage, widgets, layout, transitions, logger, PS_UNDEFINED, nothing, nothing)

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


function Term.play(handler::ProtocolScriptHandler)
  lock(handler.lock) do
    with_logger(handler.logger) do
      app = App(handler.layout; widgets = handler.widgets, expand = true, transition_rules = handler.transitions)
      play(app, transient = false)
    end
  end
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
      updateState(handler, PS_FINISHED)
    end
  end
end

function handle(handler::ProtocolScriptHandler, protocol::Protocol, event::ProgressEvent)
  handler.widgets[:progress].text = "$(event.done)/$(event.total) $(event.unit)"
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
  #menu = RadioMenu(string.(choices))
  #if handler.logger isa ProtocolScriptLogger
  #  disable(handler.logger)
  #end
  #choice = request(message, menu)
  #return choice
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