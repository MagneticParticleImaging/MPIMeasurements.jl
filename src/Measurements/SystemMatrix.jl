export measurementSystemMatrix, SystemMatrixRobotMeas

import MPIFiles.saveasMDF



struct SystemMatrixRobotMeas <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  robot::Robot
  positions::GridPositions
  signals::Array{Float32,4}
  waitTime::Float64
  controlPhase::Bool
end

function SystemMatrixRobotMeas(scanner, positions::GridPositions,params_::Dict; kargs...)
  return SystemMatrixRobotMeas(getSurveillanceUnit(scanner),
                               getDAQ(scanner),
                               getRobot(scanner),
                               getSafety(scanner), positions, params_; kargs...)
end

function SystemMatrixRobotMeas(scanner, safety, positions::GridPositions,params_::Dict; kargs...)
  return SystemMatrixRobotMeas(getSurveillanceUnit(scanner),
                               getDAQ(scanner),
                               getRobot(scanner),
                               safety, positions, params_; kargs...)
end

function SystemMatrixRobotMeas(su, daq, robot, safety, positions::GridPositions,
                     params_::Dict; controlPhase=true, waitTime = 4.0)

  updateParams!(daq, params_)

  enableACPower(su)
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
  #enableSlowDAC(daq, false)

  numSampPerPeriod = daq.params.numSampPerPeriod
  numPeriods = daq.params.acqNumPeriodsPerFrame

  signals = zeros(Float32,numSampPerPeriod,numRxChannels(daq),numPeriods,length(positions))

  measObj = SystemMatrixRobotMeas(su, daq, robot, positions, signals, waitTime, controlPhase)
  return measObj
end

function measurementSystemMatrix(su, daq, robot, safety, positions::GridPositions,
                     params_::Dict; kargs...)

  measObj = SystemMatrixRobotMeas(su, daq, robot, safety, positions, params; kargs...)

  res = performTour!(robot, safety, positions, measObj)

  # move back to park position after measurement has finished
  movePark(robot)

  stopTx(daq)
  disableACPower(su)
  disconnect(daq)

  return measObj
end

function preMoveAction(measObj::SystemMatrixRobotMeas, pos::Vector{typeof(1.0Unitful.mm)}, index)
  println("moving to next position...")
end

function postMoveAction(measObj::SystemMatrixRobotMeas, pos::Array{typeof(1.0Unitful.mm),1}, index)
  println("post action: ", pos)
  println("################## Index: ", index, " / ", length(measObj.positions))

  if measObj.controlPhase
    controlLoop(measObj.daq)
  else
    setTxParams(measObj.daq, measObj.daq.params.currTxAmp, measObj.daq.params.currTxPhase)
  end

  currFr = enableSlowDAC(measObj.daq, true, measObj.daq.params.acqNumFrameAverages,
                    measObj.daq.params.ffRampUpTime, measObj.daq.params.ffRampUpFraction)

  uMeas, uRef = readData(measObj.daq, measObj.daq.params.acqNumFrameAverages, currFr)

  setTxParams(measObj.daq, measObj.daq.params.currTxAmp*0.0, measObj.daq.params.currTxPhase*0.0)

  measObj.signals[:,:,:,index] = mean(uMeas,4)

  #sleep(measObj.waitTime)
  return uMeas, uRef
end



# high level: This stores as MDF
function measurementSystemMatrix(su, daq, robot, safety, positions::GridPositions,
                      filename::String, params_::Dict;
                       kargs...)

  measObj = measurementSystemMatrix(su, daq, robot, safety, positions, params_; kargs...)
  saveasMDF(filename, measObj, params_)
end

function saveasMDF(filename::String, measObj::SystemMatrixRobotMeas, params_::Dict)

  params = copy(params_)

  daq = measObj.daq
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
  params["rxNumSamplingPoints"] = daq.params.numSampPerPeriod #FIXME rename internally
  params["rxNumChannels"] = numRxChannels(daq)

  # calibration params  (needs to be called after calibration params!)
  #params["rxDataConversionFactor"] = calibIntToVoltRx(daq)
  calib = zeros(2,numRxChannels(daq))
  calib[1,:] = 1.0
  params["rxDataConversionFactor"] = calib

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
  params["calibFov"] = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfView(subgrid))))
  params["calibFovCenter"] = Float64.(ustrip.(uconvert.(Unitful.m, fieldOfViewCenter(subgrid))))
  params["calibSize"] = shape(subgrid)
  params["calibOrder"] = "xyz"
  if haskey(params, "calibDeltaSampleSize")
    params["calibDeltaSampleSize"] =
       Float64.(ustrip.(uconvert.(Unitful.m, params["calibDeltaSampleSize"])))
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
