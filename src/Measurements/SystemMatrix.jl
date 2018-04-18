export measurementSystemMatrix, SystemMatrixRobotMeas

struct SystemMatrixRobotMeas <: MeasObj
  su::SurveillanceUnit
  daq::AbstractDAQ
  robot::Robot
  positions::Positions
  signals::Array{Float32,4}
  waitTime::Float64
  voltToCurrent::Float64
  currents::Vector{Float64}
end

function measurementSystemMatrix(su, daq, robot, safety, positions::Positions,
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
function measurementSystemMatrix(scanner::MPIScanner, positions::Positions,
                      filename::String, params_=Dict{String,Any}();
                     bgdata=nothing, kargs...)
  merge!(daq.params, params_)

  params = copy(daq.params)

  # TODO
end


function measurementSystemMatrix(scanner::MPIScanner, positions::Positions,
                          mdf::MDFDatasetStore, params=Dict{String,Any};
                     kargs...)
  merge!(daq.params, params)

 #TODO
end
