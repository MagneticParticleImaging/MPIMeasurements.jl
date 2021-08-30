export measurementSystemMatrix, SystemMatrixRobotMeas
export init, stop, isStarted

mutable struct SystemMatrixRobotMeas <: MeasObj
  task::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  producerFinalizer::Union{Task, Nothing}
  scanner::Union{MPIScanner,Nothing}
  store::DatasetStore
  params::Dict
  positions::GridPositions
  currPos::Int
  stopped::Bool
  signals::Array{Float32,4}
  currentSignal::Array{Float32,4}
  waitTime::Float64
  measIsBGPos::Vector{Bool}
  posToIdx::Vector{Int64}
  measIsBGFrame::Vector{Bool}
  temperatures::Matrix{Float64}
  prepared::Bool
end

function SystemMatrixRobotMeas(scanner, store)
  return SystemMatrixRobotMeas(
    nothing,
    nothing, 
    nothing,
    scanner,
    store,
    Dict{String,Any}(),
    RegularGridPositions([1,1,1],[0.0,0.0,0.0],[0.0,0.0,0.0]),
    1, false, Array{Float32,4}(undef,0,0,0,0), Array{Float32,4}(undef,0,0,0,0),
    0.0, Vector{Bool}(undef,0), Vector{Int64}(undef,0), Vector{Bool}(undef,0),
    Matrix{Float64}(undef,0,0),
    false
  )
end

function cleanup(sysObj::SystemMatrixRobotMeas)
  filename = "/tmp/sysObj.toml"
  filenameSignals = "/tmp/sysObj.bin"
  rm(filename, force=true)
  rm(filenameSignals, force=true)
end

function store(sysObj::SystemMatrixRobotMeas)
  filename = "/tmp/sysObj.toml"
  rm(filename, force=true)

  params = MPIFiles.toDict(sysObj.positions)
  params["currPos"] = sysObj.currPos
  params["stopped"] = sysObj.stopped
  #params["currentSignal"] = sysObj.currentSignal
  params["waitTime"] = sysObj.waitTime
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

function restore(sysObj::SystemMatrixRobotMeas)
  filename = "/tmp/sysObj.toml"
  filenameSignals = "/tmp/sysObj.bin"

  if isfile(filename)
    params = TOML.parsefile(filename)
    sysObj.currPos = params["currPos"]
    sysObj.stopped = params["stopped"]
    #sysObj.currentSignal = params["currentSignal"]
    sysObj.waitTime = params["waitTime"]
    sysObj.measIsBGPos = params["measIsBGPos"]
    sysObj.posToIdx = params["posToIdx"]
    sysObj.measIsBGFrame = params["measIsBGFrame"]
    temp = params["temperatures"]
    if !isempty(temp) && (length(sysObj.temperatures) == length(temp))
      sysObj.temperatures[:] .= temp
    end

    sysObj.positions = Positions(params)

    daq = getDAQ(sysObj.scanner)
    numBGPos = sum(sysObj.measIsBGPos)
    numFGPos = length(sysObj.measIsBGPos) - numBGPos

    numTotalFrames = numFGPos + daq.params.acqNumBGFrames*numBGPos

    io = open(filenameSignals, "r+");
    sysObj.signals = Mmap.mmap(io, Array{Float32,4},
          (daq.params.rxNumSamplingPoints,numRxChannels(daq),
           daq.params.acqNumPeriodsPerFrame, numTotalFrames));
  end
  return
end

function init(sysObj::SystemMatrixRobotMeas, positions::GridPositions,
              params::Dict, waitTime = 4.0, safety = getSafety(sysObj.scanner))

  su = getSurveillanceUnit(sysObj.scanner)
  daq = getDAQ(sysObj.scanner)
  robot = getRobot(sysObj.scanner)
  tempSensor = getTemperatureSensor(sysObj.scanner)

  updateParams!(daq, params)

  if !daq.params.controlPhase
    # Repeated in prepareTx in asyncProducer
    tx = daq.params.calibFieldToVolt.*daq.params.dfStrength.*exp.(im*daq.params.dfPhase)
    daq.params.currTx = convert(Matrix{ComplexF64}, diagm(tx))
  end
  #setTxParams(daq, daq.params.currTx*0.0)
  #enableSlowDAC(daq, false)

  rxNumSamplingPoints = daq.params.rxNumSamplingPoints
  numPeriods = daq.params.acqNumPeriodsPerFrame

  measIsBGPos = isa(positions,BreakpointGridPositions) ?
                             MPIFiles.getmask(positions) :
                             zeros(Bool,length(positions))

  numBGPos = sum(measIsBGPos)
  numFGPos = length(measIsBGPos) - numBGPos

  numTotalFrames = numFGPos + daq.params.acqNumBGFrames*numBGPos

  currentSignal = zeros(Float32,rxNumSamplingPoints,numRxChannels(daq),numPeriods,1)
  if tempSensor != nothing
    temperatures = zeros(Float32,numChannels(tempSensor),numTotalFrames)
  else
    temperatures = zeros(0,0)
  end

  filenameSignals = "/tmp/sysObj.bin"
  io = open(filenameSignals, "w+");
  signals = Mmap.mmap(io, Array{Float32,4}, (rxNumSamplingPoints,numRxChannels(daq),numPeriods,numTotalFrames));
  signals[:] .= 0.0

  # The following looks like a secrete line but it makes sense
  posToIdx = cumsum(vcat([false],measIsBGPos)[1:end-1] .* (daq.params.acqNumBGFrames - 1) .+ 1)

  measIsBGFrame = zeros(Bool, numTotalFrames)

  sysObj.params = params
  sysObj.positions = positions
  sysObj.currPos = 1
  sysObj.stopped = false
  sysObj.signals = signals
  sysObj.currentSignal = currentSignal
  sysObj.waitTime = waitTime
  sysObj.measIsBGPos = measIsBGPos
  sysObj.posToIdx = posToIdx
  sysObj.measIsBGFrame = measIsBGFrame
  sysObj.temperatures = temperatures

  return nothing
end


function preMoveAction(measObj::SystemMatrixRobotMeas, pos::Vector{typeof(1.0Unitful.mm)}, index)
  @info "moving to position" pos
end

function postMoveAction(measObj::SystemMatrixRobotMeas,
                        pos::Array{typeof(1.0Unitful.mm),1}, index)
  @info "post action" index length(measObj.positions)

  @info "getThings"
  timeGetThings = @elapsed begin
   safety = getSafety(measObj.scanner)
   su = getSurveillanceUnit(measObj.scanner)
   daq = getDAQ(measObj.scanner)
   robot = getRobot(measObj.scanner)
   tempSensor = getTemperatureSensor(measObj.scanner)
   channel = Channel{channelType(daq)}(32)
  end

  allowControlLoop = mod1(index, 11) == 1 # Only when control loop is necessery we need to prepareTx again
  
  numFrames = measObj.measIsBGPos[index] ? daq.params.acqNumBGFrames : 1

  @info "Starting Measurement"
  timeEnableSlowDAC = @elapsed begin
    actualFrames = daq.params.acqNumFrameAverages*numFrames
    measObj.consumer = @tspawnat 3 asyncConsumer(channel, measObj, index, numFrames)
    asyncProducer(channel, daq, actualFrames, prepTx = allowControlLoop, prepSeq = false, endSeq = false)
  end
  close(channel)

  @show timeEnableSlowDAC
  measObj.producerFinalizer = @async endSequence(daq)
end

function asyncConsumer(channel::Channel, calib::SystemMatrixRobotMeas, index, numFrames)
  @info "readData"
  daq = getDAQ(calib.scanner)
  tempSensor = getTemperatureSensor(calib.scanner)
  asyncBuffer = AsyncBuffer(daq)
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(asyncBuffer, chunk)
    end
    if !isready(channel)
      sleep(0.001)
    end
  end

  uMeas, uRef = retrieveMeasAndRef!(asyncBuffer, getDAQ(calib.scanner))

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
  timeStore = @elapsed store(calib)
  @info "done"

end
###########################


function isStarted(calib::SystemMatrixRobotMeas)
  if calib.task == nothing
    return false
  else
    return !istaskdone(calib.task)
  end
end

function stop(calib::SystemMatrixRobotMeas)
  calib.stopped = true
end

function start(calib::SystemMatrixRobotMeas)
  calib.task = @tspawnat 2 performCalibrationInner(calib)
  return
end

function waitTask(task::Union{Task, Nothing})
  if !isnothing(task)
    wait(task)
  end
end

function performCalibrationInner(calib::SystemMatrixRobotMeas)
  @info  "performCalibrationInner Start"

  try

  su = getSurveillanceUnit(calib.scanner)
  daq = getDAQ(calib.scanner)
  robot = getRobot(calib.scanner)
  safety = getSafety(calib.scanner)
  tempSensor = getTemperatureSensor(calib.scanner)

  positions = calib.positions
  numPos = length(calib.positions)
  calib.stopped = false

  timeRobotMoved = 0.0

  enableACPower(su, calib.scanner)
  stopTx(daq)

  while true
    @info "Curr Pos in performCalibrationInner $(calib.currPos)"
    if calib.stopped
      # Wait for open tasks to finish (consumer will finish either way but this way we are in a known state)
      waitTask(calib.consumer)
      waitTask(calib.producerFinalizer)
      @info  "performCalibrationInner stopped"
      break
    end

    if calib.currPos <= numPos
        pos = uconvert.(Unitful.mm, positions[calib.currPos])
        
        timePreparing = @elapsed @sync begin
          # Prepare Robot/Sample
          @async moveAbsUnsafe(robot, pos) 
          # Prepare DAQ
          @async begin 
            waitTask(calib.producerFinalizer)
            prepareSequence(daq)
            prepareTx(daq, allowControlLoop = false)
            waitTask(calib.consumer)
          end
        end

        diffTime = calib.waitTime - timePreparing
        if diffTime > 0.0
          sleep(diffTime)
        end

        setEnabled(robot, false)

        timeWait = @elapsed begin
          waitTask(calib.consumer)
          waitTask(calib.producerFinalizer)
        end 

        timePostMove = @elapsed postMoveAction(calib, pos, calib.currPos)

        @info "############### Preparing Time: $(timePreparing), wait time: $timeWait, meas time: $(timePostMove)"

        setEnabled(robot, true)
        calib.currPos +=1

    end

    if calib.currPos > numPos
        waitTask(calib.consumer)
        waitTask(calib.producerFinalizer)
        @info "Store SF"
        stopTx(daq)
        disableACPower(su, calib.scanner)
        MPIMeasurements.disconnect(daq)

        movePark(robot)
        #calib.currPos = 0

        #if !calib.stopped
        saveasMDF(calib)
        #end
        break
    end

  end
  catch ex
    @warn "Exception" ex stacktrace(catch_backtrace())
  end
end

#############  Storage ##########################


function MPIFiles.saveasMDF(calibObj::SystemMatrixRobotMeas)
  store = calibObj.store
  params = calibObj.params

  if params["storeAsSystemMatrix"]
    calibNum = getNewCalibNum(store)
    params["experimentNumber"] = calibNum
    filenameA = joinpath(calibdir(store),string(calibNum)*".mdf") # just for debugging
    #filenameA = "/tmp/tmp.mdf"
    filenameB = joinpath(calibdir(store),string(calibNum+1)*".mdf")
    saveasMDF(filenameA, calibObj, params)
    #saveasMDF(filenameB, MPIFile(filenameA), applyCalibPostprocessing=true)
  else

    name = params["studyName"]
    date = params["studyDate"]
    subject = ""
  
    newStudy = Study(store, name; subject=subject, date=date)
    expNum = getNewExperimentNum(newStudy)
  
    params["experimentNumber"] = expNum
  
    filename = joinpath(path(newStudy), string(expNum)*".mdf")

    saveasMDF(filename, calibObj, params)
  end
end

function MPIFiles.saveasMDF(filename::String, measObj::SystemMatrixRobotMeas, params_::Dict)
  params = copy(params_)

  daq = getDAQ(measObj.scanner)
  positions = measObj.positions

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME

  # drivefield parameters
  params["dfStrength"] = reshape(daq.params.dfStrength,1,length(daq.params.dfStrength),1)
  params["dfPhase"] = reshape(daq.params.dfPhase,1,length(daq.params.dfPhase),1)
  params["dfDivider"] = reshape(daq.params.dfDivider,1,length(daq.params.dfDivider))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq.params.rxNumSamplingPoints
  params["rxNumChannels"] = numRxChannels(daq)

  # calibration params  (needs to be called after calibration params!)
  #params["rxDataConversionFactor"] = calibIntToVoltRx(daq)
  calib = zeros(2,numRxChannels(daq))
  calib[1,:] .= 1.0
  params["rxDataConversionFactor"] = calib

  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFrequencySelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsFastFrameAxis"] = false
  params["measIsFramePermutation"] = false

  params["acqNumFrames"] = length(measObj.measIsBGFrame)

  params["measIsBGFrame"] = measObj.measIsBGFrame

  params["measData"] = measObj.signals

  subgrid = isa(positions,BreakpointGridPositions) ? positions.grid : positions

  params["calibIsMeanderingGrid"] = isa(subgrid,MeanderingGridPositions)

  #params["calibSNR"] TODO during conversion
  params["calibFov"] = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfView(subgrid))))
  params["calibFovCenter"] = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfViewCenter(subgrid))))
  params["calibSize"] = shape(subgrid)
  params["calibOrder"] = "xyz"
  if haskey(params, "calibDeltaSampleSize")
    params["calibDeltaSampleSize"] =
       Float64.(ustrip.(uconvert.(Unitful.m, params["calibDeltaSampleSize"])))
  end
  params["calibMethod"] = "robot"

  if !isempty(measObj.temperatures)
    params["calibTemperatures"] = measObj.temperatures
  end

  @info "save as MDF"
  MPIFiles.saveasMDF( filename, params )
  @info "cleanup"
  cleanup(measObj)
  @info "done"
  return filename
end
