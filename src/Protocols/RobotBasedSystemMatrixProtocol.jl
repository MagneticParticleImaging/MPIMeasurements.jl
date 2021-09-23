export RobotBasedSystemMatrixProtocol, RobotBasedSystemMatrixProtocolParams

Base.@kwdef struct RobotBasedSystemMatrixProtocolParams <: RobotBasedProtocolParams
  waitTime::Float64
  bgFrames::Int64
  positions::Union{GridPositions, Nothing} = nothing
end
RobotBasedSystemMatrixProtocolParams(dict::Dict) = params_from_dict(RobotBasedSystemMatrixProtocolParams, dict)

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

Base.@kwdef mutable struct RobotBasedSystemMatrixProtocol <: RobotBasedProtocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::RobotBasedSystemMatrixProtocolParams
  biChannel::BidirectionalChannel{ProtocolEvent}
  
  systemMeasState::Union{SystemMatrixRobotMeas, Nothing} = nothing
  stopped::Bool = false
  cancelled::Bool = false
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

function init(protocol::RobotBasedSystemMatrixProtocol)
  protocol.systemMeasState = SystemMatrixRobotMeas()

  #Prepare Positions
  measIsBGPos = isa(protocol.params.positions,BreakpointGridPositions) ? MPIFiles.getmask(positions) : zeros(Bool,length(positions))
  numBGPos = sum(measIsBGPos)
  numFGPos = length(measIsBGPos) - numBGPos
  numTotalFrames = numFGPos + protocol.params.numBGFrames*numBGPos
  # The following looks like a secrete line but it makes sense
  posToIdx = cumsum(vcat([false],measIsBGPos)[1:end-1] .* (protocol.params.numBGFrames - 1) .+ 1)
  measIsBGFrame = zeros(Bool, numTotalFrames)

  protocol.systemMeasState.measIsBGPos = measIsBGPos
  protocol.systemMeasState.posToIdx = posToIdx
  protocol.systemMeasState.measIsBGFrame = measIsBGFrame
  protocol.systemMeasState.currPos = 1
  
  #Prepare Signals
  seq = protocol.scanner.currentSequence
  numRxChannels = length(rxChannels(seq)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
  rxNumSamplingPoints = rxNumSamplesPerPeriod(seq)
  numPeriods = acqNumPeriodsPerFrame(seq)  
  filenameSignals = "/tmp/sysObj.bin"
  io = open(filenameSignals, "w+");
  signals = Mmap.mmap(io, Array{Float32,4}, (rxNumSamplingPoints,numRxChannels,numPeriods,numTotalFrames));
  signals[:] .= 0.0 # Does this not erase our stored .bin in recovery case?
  protocol.systemMeasState.signals = signals
  
  protocol.systemMeasState.currentSignal = zeros(Float32,rxNumSamplingPoints,numRxChannels(daq),numPeriods,1)
  
  # TODO implement properly
  protocol.systemMeasState.temperatures = zeros(0, 0)
    return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function execute(protocol::RobotBasedSystemMatrixProtocol)
  @info "Start System Matrix Protocol"
  if !isReferenced(getRobot(protocol.scanner))
    put!(protocol.biChannel, ExceptionEvent("Robot not referenced! Cannot proceed!"))
    close(protocol.biChannel)
    return
  end
  
  finished = false
  started = false
  while !finished
    if !started
      #prepareCalibration/init somehow
      if isfile("/tmp/sysObj.toml")
        message = """Found existing calibration file! \n
        Should it be resumed?"""
        if askConfirmation(protocol, message)
          #restore(...) # TODO
        end
      end
    end
    finished = performCalibration(protocol)
    started = true

    while protocol.stopped
      handleEvents(protocol) # TODO cancel case
      sleep(0.05)
    end
  end

 
  put!(protocol.biChannel, FinishedNotificationEvent())
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    if protocol.cancelled
      close(protocol.biChannel)
      return
    end
    sleep(0.01)
  end
  @info "Protocol finished."
  close(protocol.biChannel)
end

function cleanup(protocol::RobotBasedSystemMatrixProtocol)
  # TODO should cleanup remove temp files? Would require a handler to differentiate between successful and unsuccesful "end"
  #filename = "/tmp/sysObj.toml"
  #filenameSignals = "/tmp/sysObj.bin"
  #rm(filename, force=true)
  #rm(filenameSignals, force=true)
end

function performCalibration(protocol::RobotBasedSystemMatrixProtocol)
  @info "Enter calibration loop"
  finished = false
  try
    calib = protocol.systemMeasState
    su = getSurveillanceUnit(protocol.scanner)
    daq = getDAQ(protocol.scanner)
    robot = getRobot(protocol.scanner)
    #safety = getSafety(protocol.scanner) #TODO fix 
    #tempSensor = getTemperatureSensor(protocol.scanner) # TODO fix
  
    positions = calib.positions
    numPos = length(calib.positions)
    
    #connect(daq)
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
        @info "Store SF"
        stopTx(daq)
        disableACPower(su, protocol.scanner)
        disconnect(daq)

        movePark(robot)

        #saveasMDF(calib)

        finished = true
        break
      end
      
    end
  
  catch ex
    @warn "Exception" ex stacktrace(catch_backtrace())
  end
  @info "Exit calibration loop"
  return finished
end

function performCalibration(protocol::RobotBasedSystemMatrixProtocol, pos)
  calib = protocol.systemMeasState
  robot = getRobot(protocol.scanner)

  timePreparing = @elapsed prepareMeasurement(protocol, pos) # TODO params

  diffTime = calib.waitTime - timePreparing
  if diffTime > 0.0
    sleep(diffTime)
  end

  setEnabled(robot, false)

  timeMeasuring = @elapsed measurement(protocol, pos)

  @info "Preptime $timePreparing, meas time: $(timeMeasuring)"

  setEnabled(robot, true)
end

function prepareMeasurement(protocol::RobotBasedSystemMatrixProtocol, pos)
  calib = protocol.systemMeasState
  robot = getRobot(protocol.scanner)
  daq = getDAQ(protocol.scanner)
  @sync begin
    # Prepare Robot/Sample
    @async timeMove = @elapsed moveAbsUnsafe(robot, pos) 
    
    # Prepare DAQ
    @async timePrepDAQ = @elapsed begin
      allowControlLoop = mod1(calib.currPos, 11) == 1  
      timeFinalizer = @elapsed wait(calib.producerFinalizer)
      timeFrameChange = @elapsed begin 
        if (calib.currPos == 1) || (calib.measIsBGPos[calib.currPos] != calib.measIsBGPos[calib.currPos-1])
          acqNumFrames(protocol.scanner.currentSequence, calib.measIsBGPos[calib.currPos] ? daq.params.acqNumBGFrames : 1)
          setSequenceParams(daq, protocol.scanner.currentSequence)
        end 
      end
      timeSeq = @elapsed prepareSequence(daq, protocol.scanner.currentSequence)
      # TODO check again if controlLoop can be run while robot is active
      timeTx = @elapsed prepareTx(daq, protocol.scanner.currentSequence, allowControlLoop = allowControlLoop)
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
    safety = getSafety(protocol.scanner)
    su = getSurveillanceUnit(protocol.scanner)
    daq = getDAQ(protocol.scanner)
    robot = getRobot(protocol.scanner)
    tempSensor = getTemperatureSensor(protocol.scanner)
    channel = Channel{channelType(daq)}(32)
  end

  @info "Starting Measurement"
  timeEnableSlowDAC = @elapsed begin
    # TODO Wait or answerEvents here?
    calib.consumer = @tspawnat protocol.scanner.generalParams.consumerThreadID asyncConsumer(channel, protocol)
    producer = @tspawnat protocol.scanner.generalParams.producerThreadID asyncProducer(channel, daq, protocol.scanner.currentSequence, prepTx = false, prepSeq = false, endSeq = false)
    while !istaskdone(producer)
      handleEvents(protocol)
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
  tempSensor = getTemperatureSensor(protocol.scanner)
  asyncBuffer = AsyncBuffer(daq)
  numFrames = acqNumFrames(protocol.scanner.currentSequence)
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
    uMeas_ = reshape(uMeas, size(uMeas,1), size(uMeas,2), size(uMeas,3),
        daq.params.acqNumFrameAverages, numFrames)
    calib.signals[:,:,:,startIdx:stopIdx] = mean(uMeas_,dims=4)[:,:,:,1,:]
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
  params["stopped"] = protocol.stopped
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
    protocol.stopped = params["stopped"]
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
    seq = protocol.scanner.currentSequence
    numRxChannels = length(rxChannels(seq)) # kind of hacky, but actual rxChannels for RedPitaya are only set when setupRx is called
    rxNumSamplingPoints = rxNumSamplesPerPeriod(seq)
    numPeriods = acqNumPeriodsPerFrame(seq)  

    io = open(filenameSignals, "r+");
    sysObj.signals = Mmap.mmap(io, Array{Float32,4},
          (rxNumSamplingPoints,numRxChannels, numPeriods, numTotalFrames));
  end
end

handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::StopEvent) = protocol.stopped = true
handleEvent(protocol::RobotBasedSystemMatrixProtocol, event::ResumeEvent) = protocol.stopped = false

function handleEvent(protocl::RobotBasedSystemMatrixProtocol, event::ProgressQueryEvent)
  put!(protocl.biChannel, ProgressEvent(protocl.systemMeasState.currPos, length(protocl.systemMeasState.positions), "Position", event))
end