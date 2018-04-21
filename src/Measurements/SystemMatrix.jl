export measurementSystemMatrix, SystemMatrixRobotMeas

struct SystemMatrixRobotMeas <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  robot::Robot
  positions::GridPositions
  signals::Array{Float32,4}
  waitTime::Float64
  voltToCurrent::Float64
  currents::Vector{Float64}
end

function measurementSystemMatrix(su, daq, robot, safety, positions::GridPositions,
                    currents, params_::Dict;
                    controlPhase=true, waitTime = 4.0,
                    voltToCurrent = 0.08547008547008547)

  updateParams!(daq, params_)

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
  end

  numSampPerPeriod = daq.params.numSampPerPeriod
  numPeriods = daq.params.acqNumPeriodsPerFrame

  signals = zeros(Float32,numSampPerPeriod,numRxChannels(daq),numPeriods,length(positions))

  measObj = SystemMatrixRobotMeas(su, daq, robot, positions, signals, waitTime,
                                  voltToCurrent, currents)

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

  setSlowDAC(measObj.daq, measObj.currents[1]*measObj.voltToCurrent, 0)
  setSlowDAC(measObj.daq, measObj.currents[2]*measObj.voltToCurrent, 1)

  sleep(0.6)

  currFr = currentFrame(measObj.daq)
  uMeas, uRef = readData(measObj.daq, 1, currFr)
  measObj.signals[:,:,:,index] = mean(uRef,4) #mean(uMeas,4)

  setSlowDAC(measObj.daq, 0.0, 0)
  setSlowDAC(measObj.daq, 0.0, 1)

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
