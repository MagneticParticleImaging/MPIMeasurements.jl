export measurementSystemMatrix, SystemMatrixRobotMeas, measurementSystemMatrixSlowFF, SystemMatrixRobotMeasSlowFF

struct SystemMatrixRobotMeasSlowFF <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  robot::Robot
  positions::GridPositions
  signals::Array{Float32,4}
  waitTime::Float64
  voltToCurrent::Float64
  currents::Matrix{Float64}
  controlPhase::Bool
end

function measurementSystemMatrixSlowFF(su, daq, robot, safety, positions::GridPositions,
                    currents, params_::Dict;
                    controlPhase=true, waitTime = 4.0,
                    voltToCurrent = 0.08547008547008547)

  updateParams!(daq, params_)

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    daq.params.currTxAmp = daq.params.calibFieldToVolt.*daq.params.dfStrength
    daq.params.currTxPhase = zeros(numTxChannels(daq))
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
  end
  setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)

  numSampPerPeriod = daq.params.numSampPerPeriod
  numPeriods = daq.params.acqNumPeriodsPerFrame

  numPatches = size(currents,2)

  signals = zeros(Float32,numSampPerPeriod,numRxChannels(daq),numPatches,length(positions))

  measObj = SystemMatrixRobotMeasSlowFF(su, daq, robot, positions, signals, waitTime,
                                  voltToCurrent, currents, controlPhase)

  res = performTour!(robot, safety, positions, measObj)

  # move back to park position after measurement has finished
  movePark(robot)

  stopTx(daq)
  disconnect(daq)

  return measObj
end

function preMoveAction(measObj::SystemMatrixRobotMeasSlowFF, pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")
end

function postMoveAction(measObj::SystemMatrixRobotMeasSlowFF, pos::Array{typeof(1.0u"mm"),1}, index)
  println("post action: ", pos)
  println("################## Index: ", index, " / ", length(measObj.positions))

  if measObj.controlPhase
    controlLoop(measObj.daq)
  else
    setTxParams(measObj.daq, measObj.daq.params.currTxAmp, measObj.daq.params.currTxPhase)
  end

  currFr = currentFrame(measObj.daq)
  uMeas, uRef = readData(measObj.daq, 1, currFr)

  u = cat(2, uMeas, uRef)

  showAllDAQData(u, showFT=true)

  setSlowDAC(measObj.daq, measObj.currents[1,1]*measObj.voltToCurrent, 0)
  setSlowDAC(measObj.daq, measObj.currents[2,1]*measObj.voltToCurrent, 1)

  sleep(1.0)

  for l=1:size(measObj.currents,2)
    # set current at DC sources
    setSlowDAC(measObj.daq, measObj.currents[1,l]*measObj.voltToCurrent, 0)
    setSlowDAC(measObj.daq, measObj.currents[2,l]*measObj.voltToCurrent, 1)

    println( "Set DC source $(measObj.currents[1,l]*u"A")  $(measObj.currents[2,l]*u"A")" )
    # wait until magnet is on field
    sleep(0.4)
    # perform MPI measurement
    currFr = currentFrame(measObj.daq)
    uMeas, uRef = readData(measObj.daq, 1, currFr)

    u = cat(2, uMeas, uRef)

    showAllDAQData(u, showFT=true)
    measObj.signals[:,:,l,index] = mean(uMeas,4)

  end
  setTxParams(measObj.daq, measObj.daq.params.currTxAmp*0.0, measObj.daq.params.currTxPhase*0.0)
  setSlowDAC(measObj.daq, 0.0, 0)
  setSlowDAC(measObj.daq, 0.0, 1)

  sleep(measObj.waitTime)
end



# high level: This stores as MDF
function measurementSystemMatrixSlowFF(su, daq, robot, safety, positions::GridPositions,
                      filename::String, currents, params_::Dict;
                       kargs...)

  params = copy(params_)

  measObj = measurementSystemMatrixSlowFF(su, daq, robot, safety, positions,
                      currents, params_; kargs...)

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqNumPeriodsPerFrame"] = size(currents,2)

  # drivefield parameters
  params["dfStrength"] = reshape(daq.params.dfStrength,1,length(daq.params.dfStrength),1)
  params["dfPhase"] = reshape(daq.params.dfPhase,1,length(daq.params.dfPhase),1)
  params["dfDivider"] = reshape(daq.params.dfDivider,1,length(daq.params.dfDivider))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq.params.numSampPerPeriod #FIXME rename internally
  params["rxNumChannels"] = numRxChannels(daq)

  # calibration params  (needs to be called after calibration params!)
  params["rxDataConversionFactor"] = calibIntToVoltRx(daq)

  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFrequencySelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsTransposed"] = false
  params["measIsFramePermutation"] = false

  params["acqNumFrames"] = length(positions)

  # TODO FIXME -> determine bg frames from positions
  params["measIsBGFrame"] = isa(positions,BreakpointGridPositions) ?
                             MPIFiles.getmask(positions) :
                             zeros(Bool,params["acqNumFrames"])
  params["measData"] = measObj.signals

  subgrid = isa(positions,BreakpointGridPositions) ? positions.grid : positions

  params["calibIsMeanderingGrid"] = isa(subgrid,MeanderingGridPositions)

  #params["calibSNR"] TODO during conversion
  params["calibFov"] = Float64.(ustrip.(uconvert.(u"m", fieldOfView(subgrid))))
  params["calibFovCenter"] = Float64.(ustrip.(uconvert.(u"m", fieldOfViewCenter(subgrid))))
  params["calibSize"] = shape(subgrid)
  params["calibOrder"] = "xyz"
  if haskey(params, "calibDeltaSampleSize")
    params["calibDeltaSampleSize"] =
       Float64.(ustrip.(uconvert.(u"m", params["calibDeltaSampleSize"])))
  end
  params["calibMethod"] = "robot"

  MPIFiles.saveasMDF( filename, params )
  return filename
end



function measurementSystemMatrix(scanner::MPIScanner, positions::Positions,
                          mdf::MDFDatasetStore, params=Dict{String,Any};
                          kargs...)
  merge!(daq.params, params)

 #TODO
end





















struct SystemMatrixRobotMeas <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  robot::Robot
  positions::GridPositions
  signals::Array{Float32,4}
  waitTime::Float64
  voltToCurrent::Float64
  currents::Vector{Float64}
  manualSeFo::Bool
  controlPhase::Bool
end

function measurementSystemMatrix(su, daq, robot, safety, positions::GridPositions,
                    currents, params_::Dict;
                    controlPhase=true, waitTime = 4.0,
                    voltToCurrent = 0.08547008547008547, manualSeFo=true)

  updateParams!(daq, params_)

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    daq.params.currTxAmp = daq.params.calibFieldToVolt.*daq.params.dfStrength
    daq.params.currTxPhase = zeros(numTxChannels(daq))
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
  end
  setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)
  enableSlowDAC(daq, false)

  numSampPerPeriod = daq.params.numSampPerPeriod
  numPeriods = daq.params.acqNumPeriodsPerFrame

  signals = zeros(Float32,numSampPerPeriod,numRxChannels(daq),numPeriods,length(positions))

  measObj = SystemMatrixRobotMeas(su, daq, robot, positions, signals, waitTime,
                                  voltToCurrent, currents, manualSeFo, controlPhase)

  res = performTour!(robot, safety, positions, measObj)

  # move back to park position after measurement has finished
  movePark(robot)

  stopTx(daq)
  disconnect(daq)

  return measObj
end

function preMoveAction(measObj::SystemMatrixRobotMeas, pos::Vector{typeof(1.0u"mm")}, index)
  println("moving to next position...")
end

function postMoveAction(measObj::SystemMatrixRobotMeas, pos::Array{typeof(1.0u"mm"),1}, index)
  println("post action: ", pos)
  println("################## Index: ", index, " / ", length(measObj.positions))

  if measObj.manualSeFo
    setSlowDAC(measObj.daq, measObj.currents[1]*measObj.voltToCurrent, 0)
    setSlowDAC(measObj.daq, measObj.currents[2]*measObj.voltToCurrent, 1)
  end

  if measObj.controlPhase
    controlLoop(measObj.daq)
  else
    setTxParams(measObj.daq, measObj.daq.params.currTxAmp, measObj.daq.params.currTxPhase)
  end

  enableSlowDAC(measObj.daq, true)
  sleep(0.6)

  currFr = currentFrame(measObj.daq)
  uMeas, uRef = readData(measObj.daq, 1, currFr)
  enableSlowDAC(measObj.daq, false)
  setTxParams(measObj.daq, measObj.daq.params.currTxAmp*0.0, measObj.daq.params.currTxPhase*0.0)

  u = cat(2, uMeas, uRef)

  showAllDAQData(u, showFT=true)

  measObj.signals[:,:,:,index] = mean(uMeas,4)


  if measObj.manualSeFo
    setSlowDAC(measObj.daq, 0.0, 0)
    setSlowDAC(measObj.daq, 0.0, 1)
  end

  sleep(measObj.waitTime)
end



# high level: This stores as MDF
function measurementSystemMatrix(su, daq, robot, safety, positions::GridPositions,
                      filename::String, currents, params_::Dict;
                       kargs...)

  params = copy(params_)

  measObj = measurementSystemMatrix(su, daq, robot, safety, positions,
                      currents, params_; kargs...)

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME

  # drivefield parameters
  params["dfStrength"] = reshape(daq.params.dfStrength,1,length(daq.params.dfStrength),1)
  params["dfPhase"] = reshape(daq.params.dfPhase,1,length(daq.params.dfPhase),1)
  params["dfDivider"] = reshape(daq.params.dfDivider,1,length(daq.params.dfDivider))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq.params.numSampPerPeriod #FIXME rename internally
  params["rxNumChannels"] = numRxChannels(daq)

  # calibration params  (needs to be called after calibration params!)
  params["rxDataConversionFactor"] = calibIntToVoltRx(daq)

  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFrequencySelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsTransposed"] = false
  params["measIsFramePermutation"] = false

  params["acqNumFrames"] = length(positions)

  # TODO FIXME -> determine bg frames from positions
  params["measIsBGFrame"] = isa(positions,BreakpointGridPositions) ?
                             MPIFiles.getmask(positions) :
                             zeros(Bool,params["acqNumFrames"])
  params["measData"] = measObj.signals

  subgrid = isa(positions,BreakpointGridPositions) ? positions.grid : positions

  params["calibIsMeanderingGrid"] = isa(subgrid,MeanderingGridPositions)

  #params["calibSNR"] TODO during conversion
  params["calibFov"] = Float64.(ustrip.(uconvert.(u"m", fieldOfView(subgrid))))
  params["calibFovCenter"] = Float64.(ustrip.(uconvert.(u"m", fieldOfViewCenter(subgrid))))
  params["calibSize"] = shape(subgrid)
  params["calibOrder"] = "xyz"
  if haskey(params, "calibDeltaSampleSize")
    params["calibDeltaSampleSize"] =
       Float64.(ustrip.(uconvert.(u"m", params["calibDeltaSampleSize"])))
  end
  params["calibMethod"] = "robot"

  MPIFiles.saveasMDF( filename, params )
  return filename
end



function measurementSystemMatrix(scanner::MPIScanner, positions::Positions,
                          mdf::MDFDatasetStore, params=Dict{String,Any};
                          kargs...)
  merge!(daq.params, params)

 #TODO
end
