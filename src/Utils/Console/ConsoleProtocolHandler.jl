export ConsoleProtocolHandler
Base.@kwdef mutable struct ConsoleProtocolHandler
  # Protocol Interaction
  scanner::MPIScanner
  protocol::Union{Protocol, Nothing} = nothing
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  eventHandler::Union{Timer, Nothing} = nothing
  protocolState::ProtocolState = PS_UNDEFINED
  updating::Bool = false
  # Display
  progress::Union{ProgressEvent, Nothing} = nothing
  progressDisplay::Union{Progress, Nothing} = nothing
  # Storage
  mdfstore::Union{MDFDatasetStore, Nothing} = nothing
  dataBGStore::Union{Array{Float32,4}, Nothing} = nothing
  currStudy::Union{MDFv2Study, Nothing} = nothing
  currExperiment::Union{MDFv2Experiment, Nothing} = nothing
  currTracer::Union{MDFv2Tracer, Nothing} = nothing
  currOperator::String = "default"
end

function ConsoleProtocolHandler(scanner::MPIScanner, protocol::Protocol)
  cph = ConsoleProtocolHandler(;scanner=scanner, protocol=protocol)
  cph.mdfstore = MDFDatasetStore(scannerDatasetStore(scanner))
  if !initProtocol(cph)
    cph = nothing
  end
  return cph
end

ConsoleProtocolHandler(scanner::MPIScanner) = ConsoleProtocolHandler(scanner, Protocol(defaultProtocol(scanner), scanner))
ConsoleProtocolHandler(scanner::String) = ConsoleProtocolHandler(MPIScanner(scanner))
function ConsoleProtocolHandler(scanner::String, protocol::String)
  scanner_ = MPIScanner(scanner)
  return ConsoleProtocolHandler(scanner_, Protocol(protocol, scanner))
end

Base.close(cph::ConsoleProtocolHandler) = close(cph.scanner)

export study
study(cph::ConsoleProtocolHandler) = cph.currStudy
study(cph::ConsoleProtocolHandler, study::MDFv2Study) = cph.currStudy = study

export experiment
experiment(cph::ConsoleProtocolHandler) = cph.currExperiment
experiment(cph::ConsoleProtocolHandler, experiment::MDFv2Experiment) = cph.currExperiment = experiment

export tracer
tracer(cph::ConsoleProtocolHandler) = cph.currTracer
tracer(cph::ConsoleProtocolHandler, tracer::MDFv2Tracer) = cph.currTracer = tracer

export operator
operator(cph::ConsoleProtocolHandler) = cph.currOperator
operator(cph::ConsoleProtocolHandler, operator::String) = cph.currOperator = operator

export initProtocol
function initProtocol(cph::ConsoleProtocolHandler)
  try 
    @info "Init protocol"
    init(cph.protocol)
    cph.biChannel = biChannel(cph.protocol)
    return true
  catch e
    @error e
    rethrow()
    #showError(e)
    return false
  end
end

export startProtocol
function startProtocol(cph::ConsoleProtocolHandler)
  try 
    @info "Execute protocol with name `$(name(cph.protocol))`"

    if isUsingMDFStudy(cph.protocol)
      if isnothing(study(cph))
        @warn "There is currently no study set. A default study is used for now. Please change to suitable values with the command `study`."
        study(cph, defaultMDFv2Study())
      end

      if isnothing(experiment(cph))
        @warn "There is currently no experiment set. A default experiment is used for now. Please change to suitable values with the command `experiment`."
        experiment(cph, defaultMDFv2Experiment())
      end

      if isnothing(tracer(cph))
        @warn "There is currently no tracer set. The protocol will start anyways. If you want to set it, you can do so with the command `tracer`."
      end
    end

    init(cph.protocol)

    cph.biChannel = execute(cph.scanner, cph.protocol)
    if isnothing(cph.biChannel)
      cph.protocolState = PS_UNDEFINED
      return false
    else
      cph.protocolState = PS_INIT
      @debug "Start event handler"
      cph.eventHandler = Timer(timer -> eventHandler(cph, timer), 0.0, interval=0.05)
      return true
    end
  catch e
    @error e
    #showError(e)
    return false
  end
end

export endProtocol
function endProtocol(cph::ConsoleProtocolHandler)
  if isnothing(cph.biChannel)
    @error "The communication channel is not available. Has the protocol been started?"
    return
  end

  if isopen(cph.biChannel)
    put!(cph.biChannel, FinishedAckEvent())
  end
  if isopen(cph.eventHandler)
    close(cph.eventHandler)
  end
  confirmFinishedProtocol(cph)
end

function eventHandler(cph::ConsoleProtocolHandler, timer::Timer)
  try
    channel = cph.biChannel
    finished = false

    if isnothing(channel)
      return
    end

    if isready(channel)
      event = take!(channel)
      @debug "Event handler received event of type $(typeof(event)) and is now dispatching it."
      finished = handleEvent(cph, cph.protocol, event)
    elseif !isopen(channel)
      finished = true
    end

    if cph.protocolState == PS_INIT && !finished
      @debug "Init query"
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      cph.protocolState = PS_RUNNING
    end

    if finished
      @info "Finished event handler"
      confirmFinishedProtocol(cph)
      close(timer)
    end

  catch ex
    @error "The eventhandler catched an exception."
    confirmFinishedProtocol(cph)
    close(timer)
    #showError(ex)
    rethrow()
  end
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::ProtocolEvent)
  @warn "No handler defined for event $(typeof(event)) and protocol $(typeof(protocol))"
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::IllegaleStateEvent)
  @error "The protocol with name `$(name(protocol))` is in an illegal state."
  cph.protocolState = PS_FAILED
  return true
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::ExceptionEvent)
  @error "Protocol exception"
  currExceptions = current_exceptions(protocol.executeTask)
  for stack in currExceptions
    showerror(stdout, stack[:exception], stack[:backtrace])
  end
  #showError(stack[1])
  cph.protocolState = PS_FAILED
  return true
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::ProgressEvent)
  channel = cph.biChannel
  # New Progress noticed
  if isopen(channel) && cph.protocolState == PS_RUNNING
    if isnothing(cph.progress) || cph.progress != event
      @debug "New progress detected"
      handleNewProgress(cph, protocol, event)
      cph.progress = event
      displayProgress(cph)
    else
      # Ask for next progress
      sleep(0.01)
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      #m.protocolStatus.waitingOnReply = progressQuery
    end
  end
  return false
end

function handleNewProgress(cph::ConsoleProtocolHandler, protocol::Protocol, event::ProgressEvent)
  if isnothing(cph.progressDisplay)
    cph.progressDisplay = Progress(event.total, 0.5)
    @debug cph.progressDisplay
  end

  progressQuery = ProgressQueryEvent()
  put!(cph.biChannel, progressQuery)
  return false
end

function displayProgress(cph::ConsoleProtocolHandler)
  if !isnothing(cph.progress)
    println("Progress: $(cph.progress.done)")
    #update!(cph.progressDisplay, cph.progress.done)
  else
    @debug "Something is strange. No progress event has yet been saved."
  end
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::DecisionEvent)
  @debug "Handling decision event for message \"$(event.message)\"."
  # options = ["Yes", "No"]
  # menu = TerminalMenus.RadioMenu(options, pagesize=2)
  # choice = TerminalMenus.request("$(event.message):", menu)

  # if choice == -1
  #   @info "Cancelled"
  # else
  #   if choice == 1
  #     reply = true
  #   elseif choice == 2
  #     reply = false
  #   else
  #     @error "Something strange happened! Please check the code!"
  #   end
  # end

  # TODO: TerminalMenus does not work properly in a threaded environment. Fix later and just return true for now.
  reply = true

  answerEvent = AnswerEvent(reply, event)
  put!(cph.biChannel, answerEvent)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::MultipleChoiceEvent)
  @debug "Handling multiple choice event for message \"$(event.message)\"."
  # menu = TerminalMenus.RadioMenu(Vector{String}(event.choices), pagesize=5)
  # reply = TerminalMenus.request("$(event.message):", menu)
  # @debug "The answer is `$(event.choices[reply])`."

  # TODO: TerminalMenus does not work properly in a threaded environment. Fix later and just return true for now.
  reply = 2
  put!(cph.biChannel, ChoiceAnswerEvent(reply, event))
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::OperationSuccessfulEvent)
  return handleSuccessfulOperation(cph, protocol, event.operation)
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::OperationNotSupportedEvent)
  return handleUnsupportedOperation(cph, protocol, event.operation)
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::OperationUnsuccessfulEvent)
  return handleUnsuccessfulOperation(cph, protocol, event.operation)
end

### Pausing/Stopping Default ###
function tryPauseProtocol(cph::ConsoleProtocolHandler)
  put!(cph.biChannel, StopEvent())
end

function handleSuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::StopEvent)
  @info "Protocol with name `$(name(protocol))` stopped"
  cph.protocolState = PS_PAUSED
  confirmPauseProtocol(cph)
  return false
end

function handleUnsupportedOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::StopEvent)
  @info "Protocol with name `$(name(protocol))` can not be stopped"
  denyPauseProtocol(cph)
  return false
end

function handleUnsuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::StopEvent)
  @info "Protocol with name `$(name(protocol))` failed to be stopped"
  denyPauseProtocol(cph)
  return false
end

function confirmPauseProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @info "The protocol with name `$(name(protocol))` was paused."
  cph.updating = false
end

function denyPauseProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @warn "Pausing the protocol with name `$(name(protocol))` was denied."
  cph.updating = false
end

### Resume/Unpause Default ###
function tryResumeProtocol(cph::ConsoleProtocolHandler)
  put!(cph.biChannel, ResumeEvent())
end

function handleSuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol with name `$(name(protocol))` resumed"
  cph.protocolState = PS_RUNNING
  confirmResumeProtocol(cph)
  put!(cph.biChannel, ProgressQueryEvent()) # Restart "Main" loop
  return false
end

function handleUnsupportedOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol with name `$(name(protocol))` cannot be resumed"
  denyResumeProtocol(cph)
  return false
end

function handleUnsuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::ResumeEvent)
  @info "Protocol with name `$(name(protocol))` failed to be resumed"
  denyResumeProtocol(cph)
  return false
end

function confirmResumeProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @info "Resuming protocol with name `$(name(protocol))`."
  cph.updating = false
end

function denyResumeProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @warn "Resuming the protocol with name `$(name(protocol))` was denied."
  cph.updating = false
end

### Cancel Default ###
function tryCancelProtocol(cph::ConsoleProtocolHandler)
  put!(cph.biChannel, CancelEvent())
end

function handleSuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::CancelEvent)
  @info "Protocol with name `$(name(protocol))` cancelled"
  cph.protocolState = PS_FAILED
  return true
end

function handleUnsupportedOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::CancelEvent)
  @warn "Protocol with name `$(name(protocol))` can not be cancelled"
  return false
end

function handleUnsuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::CancelEvent)
  @warn "Protocol with name `$(name(protocol))` failed to be cancelled"
  return false
end

### Restart Default ###
function tryRestartProtocol(cph::ConsoleProtocolHandler)
  put!(cph.biChannel, RestartEvent())
end
function handleSuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::RestartEvent)
  @info "Protocol restarted"
  confirmRestartProtocol(cph)
  return false
end

function handleUnsupportedOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::RestartEvent)
  @warn "Protocol can not be restarted"
  denyRestartProtocol(cph)
  return false
end

function handleUnsuccessfulOperation(cph::ConsoleProtocolHandler, protocol::Protocol, event::RestartEvent)
  @warn "Protocol failed to be restarted"
  denyRestartProtocol(cph)
  return false
end

function confirmRestartProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @info "Restarting protocol."
  cph.updating = false
end

function denyRestartProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @error "The protocol cannot be restarted."
  cph.updating = false
end


### Finish Default ###
function handleEvent(cph::ConsoleProtocolHandler, protocol::Protocol, event::FinishedNotificationEvent)
  cph.protocolState = PS_FINISHED
  displayProgress(cph)
  return handleFinished(cph, protocol)
end

function handleFinished(cph::ConsoleProtocolHandler, protocol::Protocol)
  put!(cph.biChannel, FinishedAckEvent())
  return true
end

function confirmFinishedProtocol(cph::ConsoleProtocolHandler)
  cph.updating = true
  @info "Confirming that the protocol is finished!"
  cph.updating = false
end

### RobotBasedSystemMatrixProtocol ###
function handleNewProgress(cph::ConsoleProtocolHandler, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  dataQuery = DataQueryEvent("SIGNAL")
  put!(cph.biChannel, dataQuery)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::RobotBasedSystemMatrixProtocol, event::DataAnswerEvent)
  channel = cph.biChannel
  if event.query.message == "SIGNAL"
    @info "Received current signal"
    frame = event.data
    if !isnothing(frame)
      #if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
        #seq = cph.protocol.params.sequence
        #deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
        #updateData(cph.rawDataWidget, frame, deltaT)
      #end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    isopen(channel) && cph.protocolState == PS_RUNNING && put!(channel, progressQuery)
  end
  return false
end

function handleFinished(cph::ConsoleProtocolHandler, protocol::RobotBasedSystemMatrixProtocol)
  request = DatasetStoreStorageRequestEvent(cph.mdfstore, getStorageMDF(cph))
  put!(cph.biChannel, request)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::RobotBasedSystemMatrixProtocol, event::StorageSuccessEvent)
  @info "Received storage success event"
  put!(cph.biChannel, FinishedAckEvent())
  cleanup(protocol)
  return true
end


### MPIMeasurementProtocol ###
function handleNewProgress(cph::ConsoleProtocolHandler, protocol::MPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  dataQuery = DataQueryEvent("FRAME:$(event.done)")
  put!(cph.biChannel, dataQuery)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::MPIMeasurementProtocol, event::DataAnswerEvent)
  channel = cph.biChannel
  # We were waiting on the last buffer request
  if startswith(event.query.message, "FRAME") && cph.protocolState == PS_RUNNING
    frame = event.data
    if !isnothing(frame)
      @debug "Received frame"
      #infoMessage(m, "$(m.progress.unit) $(m.progress.done) / $(m.progress.total)", "green")
      #if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
      #seq = cph.protocol.params.sequence
      #deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
      #updateData(cph.rawDataWidget, frame, deltaT)
      #end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    put!(channel, progressQuery)
  end
  return false
end

function handleFinished(cph::ConsoleProtocolHandler, protocol::MPIMeasurementProtocol)
  request = DatasetStoreStorageRequestEvent(cph.mdfstore, getStorageMDF(cph))
  put!(cph.biChannel, request)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::MPIMeasurementProtocol, event::StorageSuccessEvent)
  @info "Data is ready for further operations and can be found at `$(event.filename)`."
  put!(cph.biChannel, FinishedAckEvent())
  return false
end

### MechanicalMPIMeasurementProtocol ###
function handleNewProgress(cph::ConsoleProtocolHandler, protocol::MechanicalMPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  dataQuery = DataQueryEvent("FRAME:$(event.done)")
  put!(cph.biChannel, dataQuery)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::MechanicalMPIMeasurementProtocol, event::DataAnswerEvent)
  channel = cph.biChannel
  # We were waiting on the last buffer request
  if startswith(event.query.message, "FRAME") && cph.protocolState == PS_RUNNING
    frame = event.data
    if !isnothing(frame)
      @debug "Received frame"
      #infoMessage(m, "$(m.progress.unit) $(m.progress.done) / $(m.progress.total)", "green")
      #if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
      #seq = cph.protocol.params.sequence
      #deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
      #updateData(cph.rawDataWidget, frame, deltaT)
      #end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    put!(channel, progressQuery)
  end
  return false
end

function handleFinished(cph::ConsoleProtocolHandler, protocol::MechanicalMPIMeasurementProtocol)
  request = DatasetStoreStorageRequestEvent(cph.mdfstore, getStorageMDF(cph))
  put!(cph.biChannel, request)
  return false
end

function handleEvent(cph::ConsoleProtocolHandler, protocol::MechanicalMPIMeasurementProtocol, event::StorageSuccessEvent)
  @info "Data is ready for further operations and can be found at `$(event.filename)`."
  put!(cph.biChannel, FinishedAckEvent())
  return false
end



function getStorageMDF(cph::ConsoleProtocolHandler)
  mdf = defaultMDFv2InMemory()
  if !isnothing(study(cph))
    MPIFiles.study(mdf, study(cph))
  else
    @warn "The study has not been set and thus no information on it can be stored. Trying to save the data anyways to not lose it."
  end

  if !isnothing(experiment(cph))
    MPIFiles.experiment(mdf, experiment(cph))
  else
    @warn "The experiment has not been set and thus no information on it can be stored. Trying to save the data anyways to not lose it."
  end

  if !isnothing(tracer(cph))
    MPIFiles.tracer(mdf, tracer(cph))
  else
    @warn "The tracer has not been set and thus no information on it can be stored. You can set it using the command `tracer`. Trying to save the data anyways to not lose it."
  end
  
  scannerOperator(mdf, operator(cph))

  return mdf
end