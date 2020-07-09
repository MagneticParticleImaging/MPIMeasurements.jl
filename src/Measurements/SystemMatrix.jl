export measurementSystemMatrix, SystemMatrixRobotMeas
export init, stop, isStarted

mutable struct SystemMatrixRobotMeas <: MeasObj
  task::Union{Task,Nothing}
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
end

function SystemMatrixRobotMeas(scanner, store)
  return SystemMatrixRobotMeas(
    nothing,
    scanner,
    store,
    Dict{String,Any}(),
    RegularGridPositions([1,1,1],[0.0,0.0,0.0],[0.0,0.0,0.0]),
    1, false, Array{Float32,4}(undef,0,0,0,0), Array{Float32,4}(undef,0,0,0,0),
    0.0, Vector{Bool}(undef,0), Vector{Int64}(undef,0), Vector{Bool}(undef,0),
    Matrix{Float64}(undef,0,0)
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
  params["temperatures"] = sysObj.temperatures

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
    daq.params.currTxAmp = daq.params.calibFieldToVolt.*daq.params.dfStrength
    daq.params.currTxPhase = zeros(numTxChannels(daq))
  end
  #setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)
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
  end

  @info "control Phase"
  timeControlPhase = @elapsed begin
    if daq.params.controlPhase && mod1(index, 30) == 1 # only controll sometimes
      controlLoop(daq)
    else
      setTxParams(daq, daq.params.currTxAmp, daq.params.currTxPhase)
    end
  end

  numFrames = measObj.measIsBGPos[index] ? daq.params.acqNumBGFrames : 1

  @info "enableSlowDAC"
  timeEnableSlowDAC = @elapsed begin
    currFr = enableSlowDAC(daq, true, daq.params.acqNumFrameAverages*numFrames,
                    daq.params.ffRampUpTime, daq.params.ffRampUpFraction)
  end

  @info "readData"
  @show daq.params.acqNumFrameAverages numFrames currFr daq.params.ffRampUpTime daq.params.ffRampUpFraction
  timeReadData = @elapsed begin
    uMeas, uRef = readData(daq, daq.params.acqNumFrameAverages*numFrames, currFr)
  end
  @info "readData Done"

  setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)

  timeOtherThings = @elapsed begin

  startIdx = measObj.posToIdx[index]
  stopIdx = measObj.posToIdx[index] + numFrames - 1

  if measObj.measIsBGPos[index]
    uMeas_ = reshape(uMeas, size(uMeas,1), size(uMeas,2), size(uMeas,3),
                            daq.params.acqNumFrameAverages, numFrames)
    measObj.signals[:,:,:,startIdx:stopIdx] = mean(uMeas_,dims=4)[:,:,:,1,:]
  else
    measObj.signals[:,:,:,startIdx] = mean(uMeas,dims=4)
  end

  measObj.measIsBGFrame[ startIdx:stopIdx ] .= measObj.measIsBGPos[index]

  if tempSensor != nothing
    for l in startIdx:stopIdx
      for c = 1:numChannels(tempSensor)
        measObj.temperatures[c,l] = getTemperature(tempSensor, c)
      end
    end
  end



  measObj.currentSignal = uMeas[:,:,:,1:1]

  end

  @info "store"
  timeStore = @elapsed store(measObj)
  @info "done"

  allTimes = timeControlPhase+timeEnableSlowDAC+timeReadData+timeStore+timeGetThings+timeOtherThings
  @show timeGetThings timeControlPhase timeEnableSlowDAC timeReadData timeStore timeOtherThings allTimes

  return
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

  enableACPower(su)
  stopTx(daq)
  startTx(daq)

  while true
    @info "Curr Pos in performCalibrationInner $(calib.currPos)"
    if calib.stopped
      @info  "performCalibrationInner stopped"
      break
    end

    if calib.currPos <= numPos
        pos = uconvert.(Unitful.mm, positions[calib.currPos])
        timeRobotMoved = @elapsed moveAbsUnsafe(robot, pos) # comment for testing

        diffTime = calib.waitTime - timeRobotMoved
        if diffTime > 0.0
          sleep(diffTime)
        end
        yield()

        setEnabled(robot, false)
        sleep(0.1)

        timePostMove = @elapsed postMoveAction(calib, pos, calib.currPos)

        @info "############### robot move time: $(timeRobotMoved) meas time: $(timePostMove)"

        setEnabled(robot, true)
        calib.currPos +=1

    end

    if calib.currPos > numPos
        @info "Store SF"
        stopTx(daq)
        disableACPower(su)
        MPIMeasurements.disconnect(daq)

        movePark(robot)
        #calib.currPos = 0

        #if !calib.stopped
        saveasMDF(calib)
        #end
        break
    end

    if mod(calib.currPos,100) == 0
      # This is a hack. The RP gets issues when measuring to long (about 30 minutes)
      # it seems to help to restart
      stopTx(daq)
      startTx(daq)
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
    filenameA = joinpath(calibdir(store),string(calibNum)*".mdf") # just for debugging
    #filenameA = "/tmp/tmp.mdf"
    filenameB = joinpath(calibdir(store),string(calibNum+1)*".mdf")
    saveasMDF(filenameA, calibObj, params)
    saveasMDF(filenameB, MPIFile(filenameA), applyCalibPostprocessing=true)
  else

    name = params["studyName"]
    date = params["studyDate"]
    path = joinpath( studydir(store), getMDFStudyFolderName(name,date))
    subject = ""

    newStudy = Study(path,name,subject,date)

    addStudy(store, newStudy)
    expNum = getNewExperimentNum(store, newStudy)

    params["experimentNumber"] = expNum

    filename = joinpath(studydir(store),getMDFStudyFolderName(newStudy),string(expNum)*".mdf")

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
