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
  fgFrameAverages::Int64
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
  positions::Union{GridPositions, Nothing} = nothing
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
mutable struct SystemMatrixRobotMeas
  task::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  producer::Union{Task, Nothing}
  #store::DatasetStore # Do we need this?
  positions::GridPositions
  currPos::Int
  signals::Array{Float32,4}
  currentSignal::Array{Float32,4}
  measIsBGPos::Vector{Bool}
  posToIdx::Vector{Int64}
  measIsBGFrame::Vector{Bool}
  temperatures::Matrix{Float32}
end

Base.@kwdef mutable struct RobotBasedSystemMatrixProtocol <: Protocol
  @add_protocol_fields RobotBasedSystemMatrixProtocolParams
  systemMeasState::Union{SystemMatrixRobotMeas, Nothing} = nothing
  txCont::Union{TxDAQController, Nothing} = nothing
  stopped::Bool = false
  cancelled::Bool = false
  restored::Bool = false
  finishAcknowledged::Bool = false
end

function SystemMatrixRobotMeas()
  return SystemMatrixRobotMeas(
    nothing,
    nothing, 
    nothing,
    #store,
    RegularGridPositions([1,1,1],[0.0,0.0,0.0],[0.0,0.0,0.0]),
    1, Array{Float32,4}(undef,0,0,0,0), Array{Float32,4}(undef,0,0,0,0),
    Vector{Bool}(undef,0), Vector{Int64}(undef,0), Vector{Bool}(undef,0),
    Matrix{Float64}(undef,0,0))
end

function requiredDevices(protocol::RobotBasedSystemMatrixProtocol)
  result = [AbstractDAQ, Robot, SurveillanceUnit]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::RobotBasedSystemMatrixProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.systemMeasState = SystemMatrixRobotMeas()

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
  numTotalFrames = numFGPos + protocol.params.bgFrames*numBGPos
  # The following looks like a secrete line but it makes sense
  posToIdx = cumsum(vcat([false],measIsBGPos)[1:end-1] .* (protocol.params.bgFrames - 1) .+ 1)
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
  
  protocol.systemMeasState.currentSignal = zeros(Float32,rxNumSamplingPoints,numRxChannels,numPeriods,1)
  
  # TODO implement properly
  if protocol.params.saveTemperatureData
    sensor = getTemperatureSensor(protocol.scanner)
    protocol.systemMeasState.temperatures = zeros(numChannels(sensor), numBGPos + numFGPos)
  end

  # Init TxDAQController
  if protocol.params.controlTx
    controllers = getDevices(protocol.scanner, TxDAQController)
    if length(controllers) > 1
      throw(IllegalStateException("Cannot unambiguously find a TxDAQController as the scanner has $(length(controllers)) of them"))
    end
    protocol.txCont = controllers[1]
    protocol.txCont.currTx = nothing
  else
    protocol.txCont = nothing
  end

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
  if isfile("/tmp/sysObj.toml")
    message = """Found existing calibration file! \n
    Should it be resumed?"""
    if askConfirmation(protocol, message)
      restore(protocol)
    end
  end
  # Set signals to zero if we didn't restore
  if !protocol.restored
    filenameSignals = "/tmp/sysObj.bin"
    io = open(filenameSignals, "w+");
    signals = Mmap.mmap(io, Array{Float32,4}, size(protocol.systemMeasState.signals));
    protocol.systemMeasState.signals = signals  
    protocol.systemMeasState.signals[:] .= 0.0
  end
end

function _execute(protocol::RobotBasedSystemMatrixProtocol)
  @info "Start System Matrix Protocol"
  if !isReferenced(getRobot(protocol.scanner))
    throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  end

  initMeasData(protocol)
  
  finished = false
  notifiedStop = false
  while !finished
    # Perform Calibration until stopped or finished
    finished = performCalibration(protocol)

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
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.01)
  end
  @info "Protocol finished."
  close(protocol.biChannel)
end

function cleanup(protocol::RobotBasedSystemMatrixProtocol)
  # TODO should cleanup remove temp files? Would require a handler to differentiate between successful and unsuccesful "end"
  removeTempFiles(protocol)
end

function removeTempFiles(protocol::RobotBasedSystemMatrixProtocol)
  filename = "/tmp/sysObj.toml"
  filenameSignals = "/tmp/sysObj.bin"
  rm(filename, force=true)
  rm(filenameSignals, force=true)
end

function performCalibration(protocol::RobotBasedSystemMatrixProtocol)
  @info "Enter calibration loop"
  finished = false
  calib = protocol.systemMeasState
  su = getSurveillanceUnit(protocol.scanner)
  daq = getDAQ(protocol.scanner)
  robot = getRobot(protocol.scanner)

  positions = calib.positions
  numPos = length(calib.positions)
  @info "Store SF"

  stopTx(daq)
  while true
    @info "Curr Pos in performCalibrationInner $(calib.currPos)"
    handleEvents(protocol)
    
    if protocol.stopped
      wait(calib.consumer)
      wait(calib.producer)
      @info "Stop calibration loop"
      finished = false
      break
    end

    if calib.currPos <= numPos
      pos = ScannerCoords(uconvert.(Unitful.mm, positions[calib.currPos]))
      performCalibration(protocol, pos)
      calib.currPos +=1
    end

    if calib.currPos > numPos
      wait(calib.consumer)
      wait(calib.producer)
      stopTx(daq)
      disableACPower(su)
      enable(robot)
      movePark(robot)
      disable(robot)
      
      finished = true
      break
    end
    
  end
    @info "Exit calibration loop"
  return finished
end

function performCalibration(protocol::RobotBasedSystemMatrixProtocol, pos)
  calib = protocol.systemMeasState
  robot = getRobot(protocol.scanner)

  enable(robot)
  timePreparing = 0
  try 
    timePreparing = @elapsed prepareMeasurement(protocol, pos) # TODO params
  catch ex 
    if ex isa CompositeException
      @error "CompositeException while preparing measurement:"
      for e in ex
        @error e
      end
    end
    rethrow(ex)
  end

  #diffTime = protocol.params.waitTime - timePreparing
  #if diffTime > 0.0
  #  sleep(diffTime)
  #end

  disable(robot)

  timeMeasuring = @elapsed measurement(protocol)

  @info "Preptime $timePreparing, meas time: $(timeMeasuring)"

end

function prepareMeasurement(protocol::RobotBasedSystemMatrixProtocol, pos)
  @show pos
  calib = protocol.systemMeasState
  robot = getRobot(protocol.scanner)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(union(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
  timeMove = 0
  timePrepDAQ = 0
  timeFinalizer = 0
  timeFrameChange = 0
  timeSeq = 0
  timeTx = 0
  timeConsumer = 0
  timeWaitSU = 0

  @sync begin
    # Prepare Robot/Sample
    moveRobot = @tspawnat protocol.scanner.generalParams.serialThreadID begin 
      timeMove = @elapsed moveAbs(robot, pos) 
    end

    # Prepare DAQ
    @async begin
      timeFinalizer = @elapsed wait(calib.producer)
      timePrepDAQ = @elapsed @tspawnat protocol.scanner.generalParams.producerThreadID begin
        allowControlLoop = mod1(calib.currPos, 11) == 1  || protocol.restored
        # The following tasks can only be started after the finalizer and mostly only in this order
        timeFrameChange = @elapsed begin 
          if protocol.restored || (calib.currPos == 1) || (calib.measIsBGPos[calib.currPos] != calib.measIsBGPos[calib.currPos-1])
            acqNumFrames(protocol.params.sequence, calib.measIsBGPos[calib.currPos] ? protocol.params.bgFrames : 1)
            acqNumFrameAverages(protocol.params.sequence, calib.measIsBGPos[calib.currPos] ? 1 : protocol.params.fgFrameAverages)
            setup(daq, protocol.params.sequence) #TODO setupTx might be fine once while setupRx needs to be done for each new sequence
            setSequenceParams(daq, protocol.params.sequence)
            protocol.restored = false
          end
        end

        # TODO check again if controlLoop can be run while robot is active
        timeTx = @elapsed begin 
          if protocol.params.controlTx
            if allowControlLoop
              controlTx(protocol.txCont, protocol.params.sequence, protocol.txCont.currTx)
            else
              setTxParams(daq, txFromMatrix(protocol.txCont, protocol.txCont.currTx)...)
            end
          else
            prepareTx(daq, protocol.params.sequence)
          end
          setSequenceParams(daq, protocol.params.sequence) # TODO make this nicer and not redundant
        end

        suTask = @async begin
          wait(moveRobot)
          diffTime = protocol.params.waitTime - timeMove
          if diffTime > 0.0
            sleep(diffTime)
          end
          enableACPower(su)
          @sync for amp in amps
            @async turnOn(amp)
          end
        end

        timeWaitSU = @elapsed wait(suTask)
      end
    end

    @async timeConsumer = @elapsed wait(calib.consumer)
  end
  @info "############### Preparing: Move $timeMove Prep DAQ time $timePrepDAQ, Finalizer $timeFinalizer, Frame $timeFrameChange, Seq $timeSeq, SU $timeWaitSU, Tx $timeTx, Consumer $timeConsumer" 
end

function measurement(protocol::RobotBasedSystemMatrixProtocol)
  index = protocol.systemMeasState.currPos
  calib = protocol.systemMeasState
  @info "Measurement" index length(calib.positions)

  timeGetThings = @elapsed begin
    # TODO getSafety and getTempSensor if necessary
    #safety = getSafety(protocol.scanner)
    daq = getDAQ(protocol.scanner)
    su = getSurveillanceUnit(protocol.scanner)
    amps = getDevices(protocol.scanner, Amplifier)
    if !isempty(amps)
      # Only enable amps that amplify a channel of the current sequence
      channelIdx = id.(union(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
      amps = filter(amp -> in(channelId(amp), channelIdx), amps)
    end
    channel = Channel{channelType(daq)}(32)
  end

  @info "Starting Measurement"
  timeEnableSlowDAC = @elapsed begin
    calib.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(channel, protocol)
    calib.producer = @tspawnat protocol.scanner.generalParams.producerThreadID asyncProducer(channel, daq, protocol.params.sequence, prepTx = false, prepSeq = false)
    while !istaskdone(calib.producer)
      handleEvents(protocol)
      # Dont want to throw cancel here
      sleep(0.05)
    end
  end
  close(channel)

  @show timeEnableSlowDAC
  timing = getTiming(daq) 
  calib.producer = @tspawnat protocol.scanner.generalParams.producerThreadID begin
    endSequence(daq, timing.finish)
    @sync for amp in amps
      @async turnOff(amp)
    end
    disableACPower(su)
  end
end

function asyncConsumer(channel::Channel, protocol::RobotBasedSystemMatrixProtocol)
  index = protocol.systemMeasState.currPos
  calib = protocol.systemMeasState
  @info "readData"
  daq = getDAQ(protocol.scanner)
  
  tempSensor = nothing
  if protocol.params.saveTemperatureData
    tempSensor = getTemperatureSensor(protocol.scanner)
  end

  asyncBuffer = AsyncBuffer(daq)
  numFrames = acqNumFrames(protocol.params.sequence)
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(asyncBuffer, chunk)
    end
    if !isready(channel)
      sleep(0.001)
    end
  end

  uMeas, uRef = retrieveMeasAndRef!(asyncBuffer, getDAQ(protocol.scanner))

  startIdx = calib.posToIdx[index]
  stopIdx = calib.posToIdx[index] + numFrames - 1

  if calib.measIsBGPos[index]
    calib.signals[:,:,:,startIdx:stopIdx] = uMeas
  else
    calib.signals[:,:,:,startIdx] = mean(uMeas,dims=4)
  end

  calib.measIsBGFrame[ startIdx:stopIdx ] .= calib.measIsBGPos[index]

  calib.currentSignal = uMeas[:,:,:,1:1]


  if !isnothing(tempSensor)
    temps  = getTemperatures(tempSensor)
    for l in startIdx:stopIdx
      for c = 1:numChannels(tempSensor)
        calib.temperatures[c,l] = temps[c]
      end
    end
  end

  @info "store"
  timeStore = @elapsed store(protocol)
  @info "done after $timeStore"
end

function store(protocol::RobotBasedSystemMatrixProtocol)
  filename = "/tmp/sysObj.toml"
  rm(filename, force=true)

  sysObj = protocol.systemMeasState
  params = MPIFiles.toDict(sysObj.positions)
  params["currPos"] = sysObj.currPos
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
  return
end

function restore(protocol::RobotBasedSystemMatrixProtocol)
  filename = "/tmp/sysObj.toml"
  filenameSignals = "/tmp/sysObj.bin"

  sysObj = protocol.systemMeasState
  params = MPIFiles.toDict(sysObj.positions)
  if isfile(filename)
    params = TOML.parsefile(filename)
    sysObj.currPos = params["currPos"]
    protocol.stopped = false
    #params["stopped"]
    #sysObj.currentSignal = params["currentSignal"]
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

    numTotalFrames = numFGPos + protocol.params.bgFrames*numBGPos
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

    numRxChannels = length(rxChannels(seq)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
    rxNumSamplingPoints = rxNumSamplesPerPeriod(seq)
    numPeriods = acqNumPeriodsPerFrame(seq)  

    io = open(filenameSignals, "r+");
    sysObj.signals = Mmap.mmap(io, Array{Float32,4},
          (rxNumSamplingPoints,numRxChannels, numPeriods, numTotalFrames));
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
  put!(protocol.biChannel, DataAnswerEvent(protocol.systemMeasState.currentSignal, event))
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
    filename = saveasMDF(store, scanner, protocol.params.sequence, data, positions, isBackgroundFrame, mdf; storeAsSystemMatrix=protocol.params.saveAsSystemMatrix, temperatures = temperatures)
    @show filename
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::RobotBasedSystemMatrixProtocol) = Interactive()