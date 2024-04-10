export RobotBasedSystemMatrixProtocol, RobotBasedSystemMatrixProtocolParams
"""
Parameters for the RobotBasedSystemMatrixProtocol
"""
Base.@kwdef mutable struct RobotBasedSystemMatrixProtocolParams <: RobotBasedProtocolParams
  "Minimum wait time between robot movements"
  waitTime::Float64
  "Number of background frames to measure for a background position"
  bgFrames::Int64
  "Number of frames that are averaged for a foreground position"
  fgFrames::Int64
  "Flag if the calibration should be saved as a system matrix or not"
  saveAsSystemMatrix::Bool = true
  "Flag if the temperature measured after every robot measurement should be stored in the MDF or not"
  saveTemperatureData::Bool = false
  "Number of background measurements to take"
  bgMeas::Int64 = 0
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "Sequence used for the calibration at each position"
  sequence::Union{Sequence, Nothing} = nothing
  positions::Union{Positions, Nothing} = nothing
end
function RobotBasedSystemMatrixProtocolParams(dict::Dict, scanner::MPIScanner)
  if haskey(dict, "Positions")
    posDict = dict["Positions"]

    positions = Positions(posDict)
    delete!(dict, "Positions")
  else 
    positions = nothing
  end

  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  
  params = params_from_dict(RobotBasedSystemMatrixProtocolParams, dict)
  params.positions = positions
  params.sequence = sequence
  return params
end

# Based on https://github.com/MagneticParticleImaging/MPIMeasurements.jl/tree/cde1c72b820a72b3c3dfa4235b2b37bd506b0109
mutable struct SystemMatrixMeasState
  task::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  producer::Union{Task, Nothing}
  #store::DatasetStore # Do we need this?
  positions::Positions
  currPos::Int
  signals::Array{Float32,4}
  currentSignal::Array{Float32,4}
  measIsBGPos::Vector{Bool}
  posToIdx::Vector{Int64}
  measIsBGFrame::Vector{Bool}
  temperatures::Matrix{Float32}
  drivefield::Array{ComplexF64,4}
  applied::Array{ComplexF64,4}
end

Base.@kwdef mutable struct RobotBasedSystemMatrixProtocol <: RobotBasedProtocol
  @add_protocol_fields RobotBasedSystemMatrixProtocolParams
  systemMeasState::Union{SystemMatrixMeasState, Nothing} = nothing
  txCont::Union{TxDAQController, Nothing} = nothing
  contSequence::Union{ControlSequence, Nothing} = nothing
  stopped::Bool = false
  cancelled::Bool = false
  restored::Bool = false
  finishAcknowledged::Bool = false
end

function SystemMatrixMeasState()
  return SystemMatrixMeasState(
    nothing,
    nothing, 
    nothing,
    #store,
    RegularGridPositions([1,1,1],[0.0,0.0,0.0],[0.0,0.0,0.0]),
    1, Array{Float32,4}(undef,0,0,0,0), Array{Float32,4}(undef,0,0,0,0),
    Vector{Bool}(undef,0), Vector{Int64}(undef,0), Vector{Bool}(undef,0),
    Matrix{Float64}(undef,0,0), Array{ComplexF64,4}(undef,0,0,0,0), Array{ComplexF64,4}(undef,0,0,0,0))
end

function requiredDevices(protocol::RobotBasedSystemMatrixProtocol)
  result = [AbstractDAQ, Robot, SurveillanceUnit]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  if protocol.params.saveTemperatureData
    push!(result, TemperatureSensor)
  end
  return result
end

function _init(protocol::RobotBasedSystemMatrixProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.systemMeasState = SystemMatrixMeasState()

  # Prepare Positions
  # Extend Positions to include background measurements, TODO behaviour if positions already includes background pos
  cartGrid = protocol.params.positions
  if protocol.params.bgMeas == 0
    positions = cartGrid
  else
    bgIdx = round.(Int64, range(1, stop=length(cartGrid)+protocol.params.bgMeas, length=protocol.params.bgMeas ) )
    robot = getRobot(protocol.scanner)
    # BreakpointGrid can't handle ScannerCoords directly
    # But positions are (supposed to) given in ScannerCoords 
    bgRobotPos = namedPosition(robot,"park")
    bgPos = toScannerCoords(robot, bgRobotPos).data
    positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
  end
  protocol.params.positions = positions
  measIsBGPos = isa(protocol.params.positions,BreakpointGridPositions) ? MPIFiles.getmask(protocol.params.positions) : zeros(Bool,length(protocol.params.positions))
  numBGPos = sum(measIsBGPos)
  numFGPos = length(measIsBGPos) - numBGPos
  numTotalFrames = numFGPos*protocol.params.fgFrames + protocol.params.bgFrames*numBGPos
  # The following looks like a secrete line but it makes sense
  framesPerPos = zeros(length(measIsBGPos))
  posToIdx = zeros(length(measIsBGPos))
  for (i, isBg) in enumerate(measIsBGPos)
    framesPerPos[i] = isBg ? protocol.params.bgFrames : protocol.params.fgFrames
  end
  posToIdx[1] = 1
  posToIdx[2:end] = cumsum(framesPerPos)[1:end-1] .+ 1
  measIsBGFrame = zeros(Bool, numTotalFrames)

  protocol.systemMeasState.measIsBGPos = measIsBGPos
  protocol.systemMeasState.posToIdx = posToIdx
  protocol.systemMeasState.measIsBGFrame = measIsBGFrame
  protocol.systemMeasState.currPos = 1
  protocol.systemMeasState.positions = protocol.params.positions # TODO remove redundancy

  if !checkPositions(protocol)
    throw(IllegalStateException("Protocol has illegal positions"))
  end
  
  #Prepare Signals
  numRxChannels = length(rxChannels(protocol.params.sequence)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
  rxNumSamplingPoints = rxNumSamplesPerPeriod(protocol.params.sequence)
  numPeriods = acqNumPeriodsPerFrame(protocol.params.sequence)  
  signals = zeros(Float32, rxNumSamplingPoints,numRxChannels,numPeriods,numTotalFrames)
  protocol.systemMeasState.signals = signals
  
  protocol.systemMeasState.currentSignal = zeros(Float32,rxNumSamplingPoints,numRxChannels,numPeriods,protocol.params.fgFrames)
  
  # TODO implement properly
  if protocol.params.saveTemperatureData
    sensor = getTemperatureSensor(protocol.scanner)
    protocol.systemMeasState.temperatures = zeros(numChannels(sensor), numTotalFrames)
  end

  # Init TxDAQController
  if protocol.params.controlTx
    controllers = getDevices(protocol.scanner, TxDAQController)
    if length(controllers) > 1
      throw(IllegalStateException("Cannot unambiguously find a TxDAQController as the scanner has $(length(controllers)) of them"))
    end
    protocol.txCont = controllers[1]
  else
    protocol.txCont = nothing
  end
  protocol.contSequence = nothing

  return nothing
end

function checkPositions(protocol::RobotBasedSystemMatrixProtocol)
  rob = getRobot(protocol.scanner)
  valid = true
  if hasDependency(rob, AbstractCollisionModule)
    cms = dependencies(rob, AbstractCollisionModule)
    for cm in cms
      valid &= all(checkCoords(cm, protocol.params.positions))
    end
  end
  for pos in protocol.params.positions
    valid &= checkAxisRange(rob, toRobotCoords(rob, ScannerCoords(pos)))
  end
  return valid
end

function enterExecute(protocol::RobotBasedSystemMatrixProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.systemMeasState.currPos = 1
end

function initMeasData(protocol::RobotBasedSystemMatrixProtocol)
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

function cleanup(protocol::RobotBasedSystemMatrixProtocol)
  # TODO should cleanup remove temp files? Would require a handler to differentiate between successful and unsuccesful "end"
  rm(dir(protocol), force = true, recursive = true)
end

function enterPause(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  wait(calib.consumer)
  wait(calib.producer)
end

function afterMovements(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  daq = getDAQ(protocol.scanner)
  wait(calib.consumer)
  wait(calib.producer)
  stopTx(daq)
end

function nextPosition(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  if calib.currPos <= length(calib.positions)
    return ScannerCoords(uconvert.(Unitful.mm, calib.positions[calib.currPos]))
  end
  return nothing
end

function preMovement(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  @info "Curr Pos in System Matrix Protocol $(calib.currPos)"
end

function duringMovement(protocol::RobotBasedSystemMatrixProtocol, moving::Task)
  calib = protocol.systemMeasState
  wait(calib.producer)
  wait(calib.consumer)
  prepareDAQ(protocol)
end

function prepareDAQ(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  daq = getDAQ(protocol.scanner)

  sequence = protocol.params.sequence
  if protocol.params.controlTx 
    if isnothing(protocol.contSequence) || protocol.restored || (calib.currPos == 1)
      protocol.contSequence = controlTx(protocol.txCont, protocol.params.sequence)
      protocol.restored = false
    end
    if isempty(protocol.systemMeasState.drivefield)
      bufferShape = controlMatrixShape(protocol.contSequence)
      drivefield = zeros(ComplexF64, bufferShape[1], bufferShape[2], size(calib.signals, 3), size(calib.signals, 4))
      calib.drivefield = mmap!(protocol, "observedField.bin", drivefield)
      applied = zeros(ComplexF64, bufferShape[1], bufferShape[2], size(calib.signals, 3), size(calib.signals, 4))
      calib.applied = mmap!(protocol, "appliedFiled.bin", applied)
    end
    sequence = protocol.contSequence
  end
  
  acqNumFrames(sequence, calib.measIsBGPos[calib.currPos] ? protocol.params.bgFrames : protocol.params.fgFrames)
  #acqNumFrameAverages(sequence, calib.measIsBGPos[calib.currPos] ? 1 : protocol.params.fgFrames)
  acqNumFrameAverages(sequence, 1)
  setup(daq, sequence)
end

function postMovement(protocol::RobotBasedSystemMatrixProtocol)
  # Prepare
  calib = protocol.systemMeasState
  index = calib.currPos
  @info "Measurement" index length(calib.positions)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(vcat(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
  enableACPower(su)
  if tempControl != nothing
    disableControl(tempControl)
  end
  @sync for amp in amps
    @async turnOn(amp)
  end

  # Start measurement
  sequence = protocol.params.sequence
  if protocol.params.controlTx
    sequence = protocol.contSequence.targetSequence
  end

  channel = Channel{channelType(daq)}(32)
  calib.producer = @tspawnat protocol.scanner.generalParams.producerThreadID asyncProducer(channel, daq, protocol.params.sequence)
  bind(channel, calib.producer)
  calib.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(channel, protocol, index)
  while !istaskdone(calib.producer)
    handleEvents(protocol)
    # Dont want to throw cancel here
    sleep(0.05)
  end

  # Increment measured positions
  calib.currPos +=1
  
  # Start ending measurement
  calib.producer = @tspawnat protocol.scanner.generalParams.producerThreadID begin
    timing = getTiming(daq) 
    endSequence(daq, timing.finish)
    @sync for amp in amps
      @async turnOff(amp)
    end
    if tempControl != nothing
      enableControl(tempControl)
    end
    disableACPower(su)
  end
end

function asyncConsumer(channel::Channel, protocol::RobotBasedSystemMatrixProtocol, index)
  calib = protocol.systemMeasState
  @info "readData"
  daq = getDAQ(protocol.scanner)  
  numFrames = acqNumFrames(protocol.params.sequence)
  startIdx = calib.posToIdx[index]
  stopIdx = startIdx + numFrames - 1

  # Prepare Buffer
  deviceBuffer = DeviceBuffer[]
  if protocol.params.saveTemperatureData
    tempSensor = getTemperatureSensor(protocol.scanner)
    push!(deviceBuffer, TemperatureBuffer(view(calib.temperatures, :, startIdx:stopIdx), tempSensor))
  end

  sinks = StorageBuffer[]
  push!(sinks, FrameBuffer(1, view(calib.signals, :, :, :, startIdx:stopIdx)))
  sequence = protocol.params.sequence
  if protocol.params.controlTx
    sequence = protocol.contSequence
    push!(sinks, DriveFieldBuffer(1, view(calib.drivefield, :, :, :, startIdx:stopIdx), sequence))
    push!(deviceBuffer, TxDAQControllerBuffer(1, view(calib.applied, :, :, :, startIdx:stopIdx), protocol.txCont))
  end

  sequenceBuffer = AsyncBuffer(FrameSplitterBuffer(daq, sinks), daq)
  asyncConsumer(channel, sequenceBuffer, deviceBuffer)

  calib.measIsBGFrame[ startIdx:stopIdx ] .= calib.measIsBGPos[index]

  calib.currentSignal = calib.signals[:,:,:,stopIdx:stopIdx]

  step = UNCHANGED
  @time if protocol.params.controlTx
    @debug "Start update control sequence"
    field = calib.drivefield[:, :, 1, stopIdx]
    step = controlStep!(protocol.contSequence, protocol.txCont, field[:, :, 1, 1], calcDesiredField(protocol.contSequence))
    if step == INVALID
      throw(ErrorException("Control update failed to produce valid results"))
    end
    @debug "Finish update control sequence"
  end

  @info "store"
  timeStore = @elapsed store(protocol, index)
  @info "done after $timeStore"
end

function store(protocol::RobotBasedSystemMatrixProtocol, index)
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
  params["temperatures"] = vec(sysObj.temperatures)
  params["sequence"] = toDict(protocol.params.sequence)

  open(filename,"w") do f
    TOML.print(f, params)
  end

  Mmap.sync!(sysObj.signals)
  Mmap.sync!(sysObj.drivefield)
  Mmap.sync!(sysObj.applied)
  return
end

function restore(protocol::RobotBasedSystemMatrixProtocol)

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
    temp = params["temperatures"]
    if !isempty(temp) && (length(sysObj.temperatures) == length(temp))
      sysObj.temperatures[:] .= temp
    end

    sysObj.positions = Positions(params)

    numBGPos = sum(sysObj.measIsBGPos)
    numFGPos = length(sysObj.measIsBGPos) - numBGPos

    message = "Current position is $(sysObj.currPos). Resume from last background position instead?"
    if askChoices(protocol, message, ["No", "Use"]) == 2
      temp = sysObj.currPos
      while temp > 1 && !sysObj.measIsBGPos[temp]
        temp = temp - 1
      end
      sysObj.currPos = temp
    end


    seq = protocol.params.sequence

    storedSeq = sequenceFromDict(params["sequence"])
    if storedSeq != seq
      message = "Stored sequence does not match initialized sequence. Use stored sequence instead?"
      if askChoices(protocol, message, ["Cancel", "Use"]) == 1
        throw(CancelException())
      end
      seq = storedSeq
      protocol.params.sequence
    end

    # Drive Field
    if isfile(protocol, "observedField.bin") # sysObj.drivefield is still empty at point of (length(sysObj.drivefield) == length(drivefield))
      sysObj.drivefield = mmap(protocol, "observedField.bin", ComplexF64)
    end
    if isfile(protocol, "appliedField.bin")
      sysObj.applied = mmap(protocol, "appliedField.bin", ComplexF64)
    end


    sysObj.signals = mmap(protocol, "signals.bin", Float32)

    numTotalFrames = numFGPos*protocol.params.fgFrames + protocol.params.bgFrames*numBGPos
    numRxChannels = length(rxChannels(seq)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
    rxNumSamplingPoints = rxNumSamplesPerPeriod(seq)
    numPeriods = acqNumPeriodsPerFrame(seq)
    paramSize = (rxNumSamplingPoints, numRxChannels, numPeriods, numTotalFrames)
    if size(sysObj.signals) != paramSize
      throw(DimensionMismatch("Dimensions of stored signals $(size(sysObj.signals)) does not match initialized signals $paramSize"))
    end

    protocol.restored = true
    @info "Restored system matrix measurement"
  end
end


function stop(protocol::RobotBasedSystemMatrixProtocol)
  calib = protocol.systemMeasState
  if calib.currPos <= length(calib.positions)
    # OperationSuccessfulEvent is put when it actually is in the stop loop
    protocol.stopped = true
  else 
    # Stopped has no concept once all measurements are done
    put!(protocol.biChannel, OperationUnsuccessfulEvent(StopEvent()))
  end
end

function resume(protocol::RobotBasedSystemMatrixProtocol)
  protocol.stopped = false
  protocol.restored = true
  # OperationSuccessfulEvent is put when it actually leaves the stop loop
end

function cancel(protocol::RobotBasedSystemMatrixProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end


function handleEvent(protocl::RobotBasedSystemMatrixProtocol, event::ProgressQueryEvent)
  put!(protocl.biChannel, ProgressEvent(protocl.systemMeasState.currPos, length(protocl.systemMeasState.positions), "Position", event))
end

function handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::DataQueryEvent)
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

function handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::DatasetStoreStorageRequestEvent)
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
    filename = saveasMDF(store, scanner, protocol.params.sequence, data, positions, isBackgroundFrame, mdf; storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, temperatures = temperatures, drivefield = drivefield, applied = applied)
    @show filename
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::RobotBasedSystemMatrixProtocol) = Interactive()
