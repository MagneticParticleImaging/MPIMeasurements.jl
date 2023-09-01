export MultiSequenceSystemMatrixProtocol, MultiSequenceSystemMatrixProtocolParams
"""
Parameters for the MultiSequenceSystemMatrixProtocol
"""
Base.@kwdef mutable struct MultiSequenceSystemMatrixProtocolParams <: ProtocolParams
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "If the temperature should be safed or not"
  saveTemperatureData::Bool = false
  "Sequences to measure"
  sequences::Union{Vector{Sequence},Nothing} = nothing
  "SM Positions mapped to the natural sorting of sequence tomls"
  positions::Union{Positions, Nothing} = nothing
  "Flag if the calibration should be saved as a system matrix or not"
  saveAsSystemMatrix::Bool = true
  "Seconds to wait between measurements"
  waitTime::Float64 = 0.0
end
function MultiSequenceSystemMatrixProtocolParams(dict::Dict, scanner::MPIScanner)
  positions = nothing
  if haskey(dict, "Positions")
    posDict = dict["Positions"]

    positions = Positions(posDict)
    delete!(dict, "Positions")
  end


  sequence = nothing
  if haskey(dict, "sequences")
    sequences = Sequences(scanner, dict["sequences"])
    pop!(dict, "sequences")
  end
  params = params_from_dict(MultiSequenceSystemMatrixProtocolParams, dict)
  params.sequences = sequences
  params.positions = positions
  return params
end
MultiSequenceSystemMatrixProtocolParams(dict::Dict) = params_from_dict(MultiSequenceSystemMatrixProtocolParams, dict)

Base.@kwdef mutable struct MultiSequenceSystemMatrixProtocol <: Protocol
  @add_protocol_fields MultiSequenceSystemMatrixProtocolParams

  systemMeasState::Union{SystemMatrixMeasState,Nothing} = nothing

  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false
  stopped::Bool = false
  restored::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController,Nothing} = nothing
end

function requiredDevices(protocol::MultiSequenceSystemMatrixProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  if protocol.params.saveTemperatureData
    push!(result, TemperatureSensor)
  end
  return result
end

function _init(protocol::MultiSequenceSystemMatrixProtocol)
  if isnothing(protocol.params.sequences)
    throw(IllegalStateException("Protocol requires sequences"))
  end

  protocol.systemMeasState = SystemMatrixMeasState()
  numPos = length(protocol.params.sequences)
  measIsBGPos = [false for i = 1:numPos]

  framesPerPos = zeros(Int64, numPos)
  posToIdx = zeros(Int64, numPos)
  for (i, seq) in enumerate(protocol.params.sequences)
    framesPerPos[i] = acqNumFrames(seq)
  end
  numTotalFrames = sum(framesPerPos)
  posToIdx[1] = 1
  posToIdx[2:end] = cumsum(framesPerPos)[1:end-1] .+ 1
  measIsBGFrame = zeros(Bool, numTotalFrames)

  protocol.systemMeasState.measIsBGPos = measIsBGPos
  protocol.systemMeasState.posToIdx = posToIdx
  protocol.systemMeasState.measIsBGFrame = measIsBGFrame
  protocol.systemMeasState.currPos = 1
  protocol.systemMeasState.positions = protocol.params.positions

  #Prepare Signals
  numRxChannels = length(rxChannels(protocol.params.sequences[1])) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
  rxNumSamplingPoints = rxNumSamplesPerPeriod(protocol.params.sequences[1])
  numPeriods = acqNumPeriodsPerFrame(protocol.params.sequences[1])
  signals = zeros(Float32, rxNumSamplingPoints, numRxChannels, numPeriods, numTotalFrames)
  protocol.systemMeasState.signals = signals

  protocol.systemMeasState.currentSignal = zeros(Float32, rxNumSamplingPoints, numRxChannels, numPeriods, 1)



  if protocol.params.saveTemperatureData
    sensor = getTemperatureSensor(protocol.scanner)
    protocol.systemMeasState.temperatures = zeros(numChannels(sensor), numTotalFrames)
  end
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  return nothing
end

function timeEstimate(protocol::MultiSequenceSystemMatrixProtocol)
  est = "Unknown"
  #if !isnothing(protocol.params.sequence)
  #  params = protocol.params
  #  seq = params.sequence
  #  totalFrames = (params.fgFrames + params.bgFrames) * acqNumFrameAverages(seq)
  #  samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
  #  totalTime = (samplesPerFrame * totalFrames) / (125e6 / (txBaseFrequency(seq) / rxSamplingRate(seq)))
  #  time = totalTime * 1u"s"
  #  est = string(time)
  #  @show est
  #end
  return est
end

function enterExecute(protocol::MultiSequenceSystemMatrixProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.systemMeasState.currPos = 1
end

function initMeasData(protocol::MultiSequenceSystemMatrixProtocol)
  if isfile(protocol, "meta.toml")
    message = """Found existing calibration file! \n
    Should it be resumed?"""
    if askConfirmation(protocol, message)
      restore(protocol)
    end
  end
  # Set signals to zero if we didn't restore
  if !protocol.restored
    signals = mmap!(protocol, "signals.bin", protocol.systemMeasState.signals);
    protocol.systemMeasState.signals = signals  
    protocol.systemMeasState.signals[:] .= 0.0
  end
end


function _execute(protocol::MultiSequenceSystemMatrixProtocol)
  @debug "Measurement protocol started"

  initMeasData(protocol)

  finished = false
  notifiedStop = false
  while !finished
    finished = performMeasurements(protocol)

    # Stopped 
    notifiedStop = false
    while protocol.stopped
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
      if !notifiedStop
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
  end


  put!(protocol.biChannel, FinishedNotificationEvent())
  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function performMeasurements(protocol::MultiSequenceSystemMatrixProtocol)
  finished = false
  calib = protocol.systemMeasState

  while !finished
    handleEvents(protocol)

    if protocol.stopped
      enterPause(protocol)
      finished = false
      break
    end

    wait(calib.producer)
    wait(calib.consumer)
    prepareDAQ(protocol)
    # TODO wait time

    performMeasurement(protocol)
    if protocol.systemMeasState.currPos > length(protocol.params.sequences)
      calib = protocol.systemMeasState
      daq = getDAQ(protocol.scanner)
      wait(calib.consumer)
      wait(calib.producer)
      stopTx(daq)
      finished = true
    end
  end

  return finished
end

function enterPause(protocol::MultiSequenceSystemMatrixProtocol)
  calib = protocol.systemMeasState
  wait(calib.consumer)
  wait(calib.producer)
end


function performMeasurement(protocol::MultiSequenceSystemMatrixProtocol)
  # Prepare
  calib = protocol.systemMeasState
  index = calib.currPos
  @info "Measurement" index length(calib.positions)
  daq = getDAQ(protocol.scanner)

  sequence = protocol.params.sequences[index]
  #if protocol.params.controlTx
  #  sequence = protocol.contSequence.targetSequence
  #end

  channel = Channel{channelType(daq)}(32)
  calib.producer = @tspawnat protocol.scanner.generalParams.producerThreadID asyncProducer(channel, daq, sequence)
  bind(channel, calib.producer)
  calib.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(channel, protocol, index)
  while !istaskdone(calib.producer)
    handleEvents(protocol)
    # Dont want to throw cancel here
    sleep(0.05)
  end

  # Increment measured positions
  calib.currPos += 1
end

function prepareDAQ(protocol::MultiSequenceSystemMatrixProtocol)
  calib = protocol.systemMeasState
  daq = getDAQ(protocol.scanner)

  sequence = protocol.params.sequences[calib.currPos]
  if protocol.params.controlTx
    if isnothing(protocol.contSequence) || protocol.restored || (calib.currPos == 1)
      protocol.contSequence = controlTx(protocol.txCont, protocol.params.sequence)
      protocol.restored = false
    end
    #if isempty(protocol.systemMeasState.drivefield)
    #  len = length(keys(protocol.contSequence.simpleChannel))
    #  drivefield = zeros(ComplexF64, len, len, size(calib.signals, 3), size(calib.signals, 4))
    #  calib.drivefield = mmap!(protocol, "observedField.bin", drivefield)
    #  applied = zeros(ComplexF64, len, len, size(calib.signals, 3), size(calib.signals, 4))
    #  calib.applied = mmap!(protocol, "appliedFiled.bin", applied)
    #end
    sequence = protocol.contSequence
  end
  setup(daq, sequence)
end

function asyncConsumer(channel::Channel, protocol::MultiSequenceSystemMatrixProtocol, index)
  calib = protocol.systemMeasState
  @info "readData"
  daq = getDAQ(protocol.scanner)
  numFrames = acqNumFrames(protocol.params.sequences[index])
  startIdx = calib.posToIdx[index]
  stopIdx = startIdx + numFrames - 1

  # Prepare Buffer
  deviceBuffer = DeviceBuffer[]
  if protocol.params.saveTemperatureData
    tempSensor = getTemperatureSensor(protocol.scanner)
    push!(deviceBuffer, TemperatureBuffer(view(calib.temperatures, :, startIdx:stopIdx), tempSensor))
  end

  sinks = StorageBuffer[]
  push!(sinks, SimpleFrameBuffer(1, view(calib.signals, :, :, :, startIdx:stopIdx)))
  #sequence = protocol.params.sequence
  #if protocol.params.controlTx
  #  sequence = protocol.contSequence
  #  push!(sinks, DriveFieldBuffer(1, view(calib.drivefield, :, :, :, startIdx:stopIdx), sequence))
  #  push!(deviceBuffer, TxDAQControllerBuffer(1, view(calib.applied, :, :, :, startIdx:stopIdx), protocol.txCont))
  #end

  sequenceBuffer = AsyncBuffer(FrameSplitterBuffer(daq, sinks), daq)
  asyncConsumer(channel, sequenceBuffer, deviceBuffer)

  calib.measIsBGFrame[startIdx:stopIdx] .= calib.measIsBGPos[index]

  calib.currentSignal = calib.signals[:, :, :, stopIdx:stopIdx]

  @info "store"
  timeStore = @elapsed store(protocol, index)
  @info "done after $timeStore"
end

function store(protocol::MultiSequenceSystemMatrixProtocol, index)
  filename = file(protocol, "meta.toml")
  rm(filename, force=true)

  sysObj = protocol.systemMeasState
  params = MPIFiles.toDict(sysObj.positions)
  params["currPos"] = index + 1 # Safely stored up to and including index
  #params["stopped"] = protocol.stopped
  #params["currentSignal"] = sysObj.currentSignal
  params["waitTime"] = protocol.params.waitTime
  params["measIsBGPos"] = sysObj.measIsBGPos
  params["posToIdx"] = sysObj.posToIdx
  params["measIsBGFrame"] = sysObj.measIsBGFrame
  #params["temperatures"] = vec(sysObj.temperatures)
  params["sequences"] = toDict.(protocol.params.sequences)

  open(filename, "w") do f
    TOML.print(f, params)
  end

  Mmap.sync!(sysObj.signals)
  #Mmap.sync!(sysObj.drivefield)
  #Mmap.sync!(sysObj.applied)
  return
end

function restore(protocol::MultiSequenceSystemMatrixProtocol)

  sysObj = protocol.systemMeasState
  params = MPIFiles.toDict(sysObj.positions)
  if isfile(protocol, "meta.toml")
    params = TOML.parsefile(file(protocol, "meta.toml"))
    sysObj.currPos = params["currPos"]
    protocol.stopped = false
    protocol.params.waitTime = params["waitTime"]
    sysObj.measIsBGPos = params["measIsBGPos"]
    sysObj.posToIdx = params["posToIdx"]
    sysObj.measIsBGFrame = params["measIsBGFrame"]
    #temp = params["temperatures"]
    #if !isempty(temp) && (length(sysObj.temperatures) == length(temp))
    #  sysObj.temperatures[:] .= temp
    #end

    sysObj.positions = Positions(params)
    seq = protocol.params.sequences

    storedSeq = sequenceFromDict.(params["sequences"])
    if storedSeq != seq
      message = "Stored sequences do not match initialized sequence. Use stored sequence instead?"
      if askChoices(protocol, message, ["Cancel", "Use"]) == 1
        throw(CancelException())
      end
      seq = storedSeq
      protocol.params.sequence
    end

    # Drive Field
    #if isfile(protocol, "observedField.bin") # sysObj.drivefield is still empty at point of (length(sysObj.drivefield) == length(drivefield))
    #  sysObj.drivefield = mmap(protocol, "observedField.bin", ComplexF64)
    #end
    #if isfile(protocol, "appliedField.bin")
    #  sysObj.applied = mmap(protocol, "appliedField.bin", ComplexF64)
    #end


    sysObj.signals = mmap(protocol, "signals.bin", Float32)

    numTotalFrames = sum(acqNumFrames, seq)
    numRxChannels = length(rxChannels(seq[1])) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
    rxNumSamplingPoints = rxNumSamplesPerPeriod(seq[1])
    numPeriods = acqNumPeriodsPerFrame(seq[1])
    paramSize = (rxNumSamplingPoints, numRxChannels, numPeriods, numTotalFrames)
    if size(sysObj.signals) != paramSize
      throw(DimensionMismatch("Dimensions of stored signals $(size(sysObj.signals)) does not match initialized signals $paramSize"))
    end

    protocol.restored = true
    @info "Restored system matrix measurement"
  end
end



function cleanup(protocol::MultiSequenceSystemMatrixProtocol)
  rm(dir(protocol), force = true, recursive = true)
end

function stop(protocol::MultiSequenceSystemMatrixProtocol)
  calib = protocol.systemMeasState
  if calib.currPos <= length(calib.positions)
    # OperationSuccessfulEvent is put when it actually is in the stop loop
    protocol.stopped = true
  else
    # Stopped has no concept once all measurements are done
    put!(protocol.biChannel, OperationUnsuccessfulEvent(StopEvent()))
  end
end

function resume(protocol::MultiSequenceSystemMatrixProtocol)
  protocol.stopped = false
  protocol.restored = true
  # OperationSuccessfulEvent is put when it actually leaves the stop loop
end

function cancel(protocol::MultiSequenceSystemMatrixProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end


function handleEvent(protocl::MultiSequenceSystemMatrixProtocol, event::ProgressQueryEvent)
  put!(protocl.biChannel, ProgressEvent(protocl.systemMeasState.currPos, length(protocl.params.sequences), "Position", event))
end

function handleEvent(protocol::MultiSequenceSystemMatrixProtocol, event::DataQueryEvent)
  data = nothing
  if event.message == "CURR"
    data = protocol.systemMeasState.currentSignal
  elseif event.message == "BG"
    sysObj = protocol.systemMeasState
    index = sysObj.currPos
    while index > 1 && !sysObj.measIsBGPos[index]
      index = index - 1
    end
    startIdx = sysObj.posToIdx[index]
    data = copy(sysObj.signals[:, :, :, startIdx:startIdx])
  else
    put!(protocol.biChannel, UnknownDataQueryEvent(event))
  end
  put!(protocol.biChannel, DataAnswerEvent(data, event))
end

function handleEvent(protocol::MultiSequenceSystemMatrixProtocol, event::DatasetStoreStorageRequestEvent)
  if false
    # TODO this should be some sort of storage failure event
    put!(protocol.biChannel, IllegaleStateEvent("Calibration measurement is not done yet. Cannot save!"))
  else
    store = event.datastore
    scanner = protocol.scanner
    mdf = event.mdf
    data = protocol.systemMeasState.signals
    positions = protocol.systemMeasState.positions
    isBackgroundFrame = protocol.systemMeasState.measIsBGFrame
    temperatures = nothing
    if protocol.params.saveTemperatureData
      temperatures = protocol.systemMeasState.temperatures
    end
    drivefield = nothing
    if !isempty(protocol.systemMeasState.drivefield)
      drivefield = protocol.systemMeasState.drivefield
    end
    applied = nothing
    if !isempty(protocol.systemMeasState.applied)
      applied = protocol.systemMeasState.applied
    end
    filename = saveasMDF(store, scanner, protocol.params.sequences[1], data, positions, isBackgroundFrame, mdf; storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, temperatures=temperatures, drivefield=drivefield, applied=applied)
    @show filename
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::MultiSequenceSystemMatrixProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::MultiSequenceSystemMatrixProtocol) = Interactive()
protocolMDFStudyUse(protocol::MultiSequenceSystemMatrixProtocol) = UsingMDFStudy()
