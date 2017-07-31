export measurement, measurementCont

function measurement(daq::AbstractDAQ, params=Dict{String,Any}();
                     controlPhase=false )

  updateParams(daq, params)

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq["calibFieldToVolt"].*daq["dfStrength"],
                     zeros(numTxChannels(daq)))
  end
  currFr = currentFrame(daq)

  #buffer = zeros(Float32,numSampPerPeriod, numChannels, numFrames)
  #for n=1:numFrames
  #  uMeas = readData(daq, 1, currFr+(n-1)*numAverages, numAverages)
  #    uMeas = mean(uMeas,2)
  #  buffer[:,n] = uMeas
  #end
  uMeas, uRef = readData(daq, daq["acqNumFGFrames"], currFr)

  stopTx(daq)

  return uMeas
end

# high level: This stores as MDF
function measurement(daq::AbstractDAQ, filename::String, params_=Dict{String,Any}();
                     bgdata=nothing, kargs...)
  updateParams(daq, params_)

  params = copy(daq.params)

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME

  # drivefield parameters
  params["dfStrength"] = reshape(daq["dfStrength"],1,length(daq["dfStrength"]),1)
  params["dfPhase"] = reshape(daq["dfPhase"],1,length(daq["dfPhase"]),1)
  params["dfDivider"] = reshape(daq["dfDivider"],1,length(daq["dfDivider"]))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq["numSampPerPeriod"] #FIXME rename internally

  # transferFunction
  if params["transferFunction"] != ""
    numFreq = div(params["rxNumSamplingPoints"],2)+1
    freq = collect(0:(numFreq-1))./(numFreq-1).*daq["rxBandwidth"]
    tf = zeros(Complex128, numFreq, numRxChannels(daq) )
    tf_ = tf_receive_chain(params["transferFunction"])
    for d=1:numRxChannels(daq)
      tf[:,d] = tf_[freq,d]
    end
    params["rxTransferFunction"] = tf
    params["rxInductionFactor"] = tf_.inductionFactor
  end

  # measurement
  uFG = measurement(daq; kargs...)

  # calibration params  (needs to be called after calibration params!)
  params["rxDataConversionFactor"] = dataConversionFactor(daq)

  if bgdata == nothing
    params["measIsBGFrame"] = zeros(Bool,daq["acqNumFGFrames"])
    params["measData"] = uFG
    params["acqNumFrames"] = daq["acqNumFGFrames"]
  else
    numBGFrames = size(bgdata,4)
    params["measData"] = cat(4,bgdata,uFG)
    params["measIsBGFrame"] = cat(1, ones(Bool,numBGFrames), zeros(Bool,daq["acqNumFGFrames"]))
    params["acqNumFrames"] = daq["acqNumFGFrames"] + numBGFrames
  end

  MPIFiles.saveasMDF( filename, params )
  return filename
end


function measurement(daq::AbstractDAQ, mdf::MDFDatasetStore, params=Dict{String,Any};
                     kargs...)
  updateParams(daq, params)

  name = params["studyName"]
  path = joinpath( studydir(mdf), name)
  subject = ""
  date = ""

  newStudy = Study(path,name,subject,date)

  addStudy(mdf, newStudy)
  expNum = getNewExperimentNum(mdf, newStudy)

  daq["studyName"] = params["studyName"]
  daq["experimentNumber"] = expNum

  filename = joinpath(studydir(mdf),newStudy.name,string(expNum)*".mdf")
  measurement(daq, filename; kargs...)
  return filename
end


export loadBGCorrData
function loadBGCorrData(filename)
  f = MPIFiles.MPIFile(filename)
  u = MPIFiles.measData(f)[:,1,1,measFGFrameIdx(f)]
  if acqNumBGFrames(f) > 0
    uBG = MPIFiles.measData(f)[:,1,1,measBGFrameIdx(f)]
    uBGMean = mean(uBG[:,:],2)
    u[:] .-= uBGMean
  end
  return u
end


function measurementCont(daq::AbstractDAQ)
  startTx(daq)

  controlLoop(daq)

  try
      while true
        uMeas, uRef = readData(daq,1, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        amplitude, phase = calcFieldFromRef(daq,uRef)
        println("reference amplitude=$amplitude phase=$phase")

        showAllDAQData(uMeas,1)
        showAllDAQData(uRef,2)
        sleep(0.01)
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(daq)
      else
        rethrow(x)
      end
  end
end
