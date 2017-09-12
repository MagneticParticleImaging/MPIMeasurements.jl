export measurementSystemMatrix, SystemMatrixRobotMeas

struct SystemMatrixRobotMeas <: MeasObj
  daq::AbstractDAQ
  robot::Robot
  positions::Array{Vector{typeof(1.0u"mm")},1}
  signals::Array{Float32,4}
end

function measurementSystemMatrix(scanner::MPIScanner, positions::Positions,
                    params=Dict{String,Any}();
                    controlPhase=true)

  robot = getRobot(scanner)
  daq = getDAQ(scanner)

  merge!(daq.params, params)

  scannerSetup = dSampleRegularScanner

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq["calibFieldToVolt"].*daq["dfStrength"],
                     zeros(numTxChannels(daq)))
  end

  numSampPerPeriod = daq["numSampPerPeriod"]
  numPeriods = daq["acqNumPeriods"]

  signals = zeros(Float32,numSampPerPeriod,numRxChannels(daq),numPeriods,length(positions))

  measObj = SystemMatrixRobotMeas(daq, robot,
                            Array{Vector{typeof(1.0u"mm")},1}(),
                            signals)

  res = performTour!(robot, scannerSetup, positions, measObj)

  #move back to park position after measurement has finished
  movePark(robot)
  stopTx(daq)

  return measObj
end

function preMoveAction(measObj::SystemMatrixRobotMeas, pos::Array{typeof(1.0u"mm"),1}, index)
  # nothing todo
end

function postMoveAction(measObj::SystemMatrixRobotMeas, pos::Array{typeof(1.0u"mm"),1}, index)
  println("post action: ", pos)
  push!(measObj.positions, pos)

  currFr = currentFrame(measObj.daq)
  uMeas, uRef = readData(measObj.daq, measObj.daq["acqNumFGFrames"], currFr)
  measObj.signals[:,:,:,index] = mean(uRef,4) #mean(uMeas,4)
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
