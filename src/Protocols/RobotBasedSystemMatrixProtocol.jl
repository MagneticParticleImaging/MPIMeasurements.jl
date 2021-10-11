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
  "Number of background measurements to take"
  bgMeas::Int64 = 0
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
  producerFinalizer::Union{Task, Nothing}
  #store::DatasetStore # Do we need this?
  positions::GridPositions
  currPos::Int
  signals::Array{Float32,4}
  currentSignal::Array{Float32,4}
  measIsBGPos::Vector{Bool}
  posToIdx::Vector{Int64}
  measIsBGFrame::Vector{Bool}
  temperatures::Matrix{Float64}
end

Base.@kwdef mutable struct RobotBasedSystemMatrixProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::RobotBasedSystemMatrixProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  
  executeTask::Union{Task, Nothing} = nothing
  systemMeasState::Union{SystemMatrixRobotMeas, Nothing} = nothing
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

function _init(protocol::RobotBasedSystemMatrixProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.systemMeasState = SystemMatrixRobotMeas()

  #Prepare Positions
  # Extend Positions to include background measurements
  cartGrid = protocol.params.positions
  if protocol.params.bgMeas == 0
    positions = cartGrid
  else
    bgIdx = round.(Int64, range(1, stop=length(cartGrid)+protocol.params.bgMeas, length=protocol.params.bgMeas ) )
    bgPos = namedPosition(getRobot(protocol.scanner),"park")
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
  
  #Prepare Signals
  numRxChannels = length(rxChannels(protocol.params.sequence)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
  rxNumSamplingPoints = rxNumSamplesPerPeriod(protocol.params.sequence)
  numPeriods = acqNumPeriodsPerFrame(protocol.params.sequence)  
  filenameSignals = "/tmp/sysObj.bin"
  io = open(filenameSignals, "w+");
  signals = Mmap.mmap(io, Array{Float32,4}, (rxNumSamplingPoints,numRxChannels,numPeriods,numTotalFrames));
  signals[:] .= 0.0 # Does this not erase our stored .bin in recovery case?
  protocol.systemMeasState.signals = signals
  
  protocol.systemMeasState.currentSignal = zeros(Float32,rxNumSamplingPoints,numRxChannels,numPeriods,1)
  
  # TODO implement properly
  protocol.systemMeasState.temperatures = zeros(0, 0)

  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
end

function _execute(protocol::RobotBasedSystemMatrixProtocol)
  @info "Start System Matrix Protocol"
  #if !isReferenced(getRobot(protocol.scanner))
  #  throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  #end
  # TODO THIS SHOULD HAPPEN EXTERNALLY
  robot = getRobot(protocol.scanner)
  enable(robot)
  doReferenceDrive(robot)
  
  finished = false
  started = false
  notifiedStop = false
  while !finished
    if !started
      if isfile("/tmp/sysObj.toml")
        message = """Found existing calibration file! \n
        Should it be resumed?"""
        if askConfirmation(protocol, message)
          restore(protocol)
        end
      end
    end
    finished = performCalibration(protocol)
    started = true

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
  #safety = getSafety(protocol.scanner) #TODO fix 
  #safety = getSafety(protocol.scanner) #TODO fix 
  #tempSensor = getTemperatureSensor(protocol.scanner) # TODO fix

  positions = calib.positions
  numPos = length(calib.positions)
  @info "Store SF"

  enableACPower(su, protocol.scanner)
  stopTx(daq)
  while true
    @info "Curr Pos in performCalibrationInner $(calib.currPos)"
    handleEvents(protocol)
    
    if protocol.stopped
      wait(calib.consumer)
      wait(calib.producerFinalizer)
      @info "Stop calibration loop"
      finished = false
      break
    end

    if calib.currPos <= numPos
      pos = uconvert.(Unitful.mm, positions[calib.currPos])
      performCalibration(protocol, pos)
      calib.currPos +=1
    end

    if calib.currPos > numPos
      wait(calib.consumer)
      wait(calib.producerFinalizer)
      stopTx(daq)
      disableACPower(su, protocol.scanner)
      enable(robot)
      movePark(robot)
      disable(robot)
      #saveasMDF(calib) # TODO implement saving
      #removeTempFiles(protocol)
      
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
  timePreparing = @elapsed prepareMeasurement(protocol, pos) # TODO params

  diffTime = protocol.params.waitTime - timePreparing
  if diffTime > 0.0
    sleep(diffTime)
  end

  disable(robot)

  timeMeasuring = @elapsed measurement(protocol)

  @info "Preptime $timePreparing, meas time: $(timeMeasuring)"

end

function prepareMeasurement(protocol::RobotBasedSystemMatrixProtocol, pos)
  calib = protocol.systemMeasState
  robot = getRobot(protocol.scanner)
  daq = getDAQ(protocol.scanner)
  timePrepDAQ = 0
  timeFinalizer = 0
  timeFrameChange = 0
  timeSeq = 0
  timeTx = 0
  timeConsumer = 0

  @sync begin
    # Prepare Robot/Sample
    @async timeMove = @elapsed moveAbs(robot, pos) 
    
    # Prepare DAQ
    @async timePrepDAQ = @elapsed begin
      allowControlLoop = mod1(calib.currPos, 11) == 1  
      timeFinalizer = @elapsed wait(calib.producerFinalizer)
      timeFrameChange = @elapsed begin 
        if protocol.restored || (calib.currPos == 1) || (calib.measIsBGPos[calib.currPos] != calib.measIsBGPos[calib.currPos-1])
          acqNumFrames(protocol.params.sequence, calib.measIsBGPos[calib.currPos] ? protocol.params.bgFrames : 1)
          acqNumFrameAverages(protocol.params.sequence, calib.measIsBGPos[calib.currPos] ? 1 : protocol.params.fgFrameAverages)
          setup(daq, protocol.params.sequence) #TODO setupTx might be fine once while setupRx needs to be done for each new sequence
          setSequenceParams(daq, protocol.params.sequence)
          protocol.restored = false
        end 
      end

      timeSeq = @elapsed prepareSequence(daq, protocol.params.sequence)
      # TODO check again if controlLoop can be run while robot is active
      timeTx = @elapsed prepareTx(daq, protocol.params.sequence, allowControlLoop = false)
    end

    @async timeConsumer = @elapsed wait(calib.consumer)
  end
  @info "############### Preparing: Prep DAQ time $timePrepDAQ, Finalizer $timeFinalizer, Frame $timeFrameChange, Seq $timeSeq, Tx $timeTx, Consumer $timeConsumer" 
end

function measurement(protocol::RobotBasedSystemMatrixProtocol)
  index = protocol.systemMeasState.currPos
  calib = protocol.systemMeasState
  @info "Measurement" index length(calib.positions)

  timeGetThings = @elapsed begin
    # TODO getSafety and getTempSensor if necessary
    #safety = getSafety(protocol.scanner)
    su = getSurveillanceUnit(protocol.scanner)
    daq = getDAQ(protocol.scanner)
    robot = getRobot(protocol.scanner)
    #tempSensor = getTemperatureSensor(protocol.scanner)
    channel = Channel{channelType(daq)}(32)
  end

  @info "Starting Measurement"
  timeEnableSlowDAC = @elapsed begin
    # TODO Wait or answerEvents here?
    calib.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(channel, protocol)
    producer = @tspawnat protocol.scanner.generalParams.producerThreadID asyncProducer(channel, daq, protocol.params.sequence, prepTx = false, prepSeq = false, endSeq = false)
    while !istaskdone(producer)
      handleEvents(protocol)
      # Dont want to throw cancel here
      sleep(0.05)
    end
  end
  close(channel)

  @show timeEnableSlowDAC
  start, endFrame = getFrameTiming(daq) 
  calib.producerFinalizer = @async endSequence(daq, endFrame)
end

function asyncConsumer(channel::Channel, protocol::RobotBasedSystemMatrixProtocol)
  index = protocol.systemMeasState.currPos
  calib = protocol.systemMeasState
  @info "readData"
  daq = getDAQ(protocol.scanner)
  #tempSensor = getTemperatureSensor(protocol.scanner)
  tempSensor = nothing
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
    for l in startIdx:stopIdx
      for c = 1:numChannels(tempSensor)
        calib.temperatures[c,l] = getTemperature(tempSensor, c)
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
    params = event.params
    data = protocol.systemMeasState.signals
    positions = protocol.systemMeasState.positions
    isBackgroundFrame = protocol.systemMeasState.measIsBGFrame
    params["storeAsSystemMatrix"] = protocol.params.saveAsSystemMatrix
    filename = saveasMDF(store, scanner, protocol.params.sequence, data, positions, isBackgroundFrame, params)
    @show filename
    put!(protocol.biChannel, StorageSuccessEvent(filename))
  end
end

handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::RobotBasedSystemMatrixProtocol) = Interactive()