export measurement, asyncMeasurement, measurementCont, measurementRepeatability,
       MeasState

function measurement(daq::AbstractDAQ, params_::Dict;
                     kargs... )
  updateParams!(daq, params_)
  measurement_(daq; kargs...)
end

function measurement_(daq::AbstractDAQ)

  startTxAndControl(daq)

  currFr = enableSlowDAC(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
                         daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

  uMeas, uRef = readData(daq, daq.params.acqNumFrames*daq.params.acqNumFrameAverages, currFr)
  # sleep(daq.params.ffRampUpTime)    ### This should be analog to asyncMeasurementInner
  stopTx(daq)
  disconnect(daq)

  if daq.params.acqNumFrameAverages > 1
    u_ = reshape(uMeas, size(uMeas,1), size(uMeas,2), size(uMeas,3),
                daq.params.acqNumFrames,daq.params.acqNumFrameAverages)
    uMeasAv = mean(u_, dims=5)[:,:,:,:,1]
    return uMeasAv
  else
    return uMeas
  end
end

function MPIFiles.saveasMDF(filename::String, daq::AbstractDAQ, data::Array{Float32,4},
                             params::Dict; bgdata=nothing, auxData=nothing )

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

  # transferFunction
  if haskey(params, "transferFunction") && params["transferFunction"] != ""
    numFreq = div(params["rxNumSamplingPoints"],2)+1
    freq = collect(0:(numFreq-1))./(numFreq-1).*daq.params.rxBandwidth
    #tf = zeros(ComplexF64, numFreq, numRxChannels(daq) )
    #tf_ = tf_receive_chain()
    tf_ =  TransferFunction(params["transferFunction"])
    #for d=1:numRxChannels(daq)
    #  tf[:,d] = tf_[freq,d]
    #end
    tf = tf_[freq,1:numRxChannels(daq)]
    params["rxTransferFunction"] = tf
    params["rxInductionFactor"] = tf_.inductionFactor
  end

  # calibration params  (needs to be called after calibration params!)
  calib = zeros(2,numRxChannels(daq))
  calib[1,:] .= 1.0
  params["rxDataConversionFactor"] = calib # calibIntToVoltRx(daq)

  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFrequencySelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsFastFrameAxis"] = false
  params["measIsFramePermutation"] = false

  if bgdata == nothing
    params["measIsBGFrame"] = zeros(Bool,params["acqNumFrames"])
    params["measData"] = data
    #params["acqNumFrames"] = params["acqNumFGFrames"]
  else
    numBGFrames = size(bgdata,4)
    params["measData"] = cat(bgdata,data,dims=4)
    params["measIsBGFrame"] = cat(ones(Bool,numBGFrames), zeros(Bool,params["acqNumFrames"]), dims=1)
    params["acqNumFrames"] = params["acqNumFrames"] + numBGFrames
  end

  if auxData != nothing
    params["auxiliaryData"] = auxData
  end

  MPIFiles.saveasMDF( filename, params )
  return filename
end

function MPIFiles.saveasMDF(store::DatasetStore, daq::AbstractDAQ, data::Array{Float32,4},
                             params::Dict; kargs...)

  name = params["studyName"]
  date = params["studyDate"]
  path = joinpath( studydir(store), getMDFStudyFolderName(name,date))
  subject = ""

  newStudy = Study(path,name,subject,date)

  addStudy(store, newStudy)
  expNum = getNewExperimentNum(store, newStudy)

  #daq["studyName"] = params["studyName"]
  params["experimentNumber"] = expNum

  filename = joinpath(studydir(store), getMDFStudyFolderName(newStudy), string(expNum)*".mdf")

  saveasMDF(filename, daq, data, params; kargs... )

  return filename
end

### high level: This stores as MDF
function measurement(daq::AbstractDAQ, params_::Dict, filename::String;
                     bgdata=nothing, auxData=nothing, kargs...)

  params = copy(params_)
  data, auxData = measurement(daq, params; kargs...)
  saveasMDF(filename, daq, data, params; bgdata=bgdata, auxData=auxData)
  return nothing
end

function measurement(daq::AbstractDAQ, params::Dict, store::DatasetStore;
                     bgdata=nothing, auxData=nothing, kargs...)

   params = copy(params_)
   data, auxData = measurement(daq, params; kargs...)
   saveasMDF(store, daq, data, params; bgdata=bgdata, auxData=auxData)
   return nothing
end

####  Async version  ####

mutable struct MeasState
  task::Union{Task,Nothing}
  numFrames::Int
  currFrame::Int
  cancelled::Bool
  buffer::Array{Float32,4}
  consumed::Bool
  filename::String
  temperatures::Matrix{Float64}
end

MeasState() = MeasState(nothing, 0, 0, false, zeros(Float64,0,0,0,0), false, "", zeros(Float64,0,0))

function cancel(calibState::MeasState)
  measState.cancelled = true
  measState.consumed = true
end

function asyncMeasurement(scanner::MPIScanner, store::DatasetStore, params_::Dict, bgdata=nothing)
  daq = getDAQ(scanner)
  params = copy(params_)
  updateParams!(daq, params_)
  params["dfCycle"] = daq.params.dfCycle # pretty bad hack

  numFrames = daq.params.acqNumFrames
  rxNumSamplingPoints = daq.params.rxNumSamplingPoints
  numPeriods = daq.params.acqNumPeriodsPerFrame
  buffer = zeros(Float32,rxNumSamplingPoints,numRxChannels(daq),numPeriods,numFrames)

  measState = MeasState(nothing, numFrames, 0, false, buffer, false, "", zeros(Float64,0,0))
  measState.task = @tspawnat 2 asyncMeasurementInner(measState,scanner,store,params,bgdata)
  #measState.task = Threads.@spawn asyncMeasurementInner(measState,scanner,store,params,bgdata)

  return measState
end

function asyncMeasurementInner(measState::MeasState, scanner::MPIScanner,
                                 store::DatasetStore, params::Dict, bgdata=nothing)
  #try
    su = getSurveillanceUnit(scanner)
    daq = getDAQ(scanner)
    tempSensor = getTemperatureSensor(scanner)

    if tempSensor != nothing
      measState.temperatures = zeros(Float32, numChannels(tempSensor), daq.params.acqNumFrames)
    end

    setEnabled(getRobot(scanner), false)
    enableACPower(su, scanner)

    startTxAndControl(daq)

    currFr = enableSlowDAC(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
                           daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

    for fr=1:daq.params.acqNumFrames
      if tempSensor != nothing
        for c = 1:numChannels(tempSensor)
            measState.temperatures[c,fr] = getTemperature(tempSensor, c)
        end
      end
      #println("FRAME NEU $fr")
      uMeas, uRef = readData(daq, daq.params.acqNumFrameAverages,
                                  currFr + (fr-1)*daq.params.acqNumFrameAverages)

      measState.buffer[:,:,:,fr] = mean(uMeas, dims=4)
      measState.currFrame = fr
      measState.consumed = false
      #sleep(0.01)
      #yield()
      if measState.cancelled
        break
      end
    end
    sleep(daq.params.ffRampUpTime)
    stopTx(daq)
    disableACPower(su, scanner)
    disconnect(daq)
    setEnabled(getRobot(scanner), true)

    if length(measState.temperatures) > 0
      params["calibTemperatures"] = measState.temperatures
    end

    measState.filename = saveasMDF(store, daq, measState.buffer, params; bgdata=bgdata) #, auxData=auxData)
  #catch ex
  #  @warn "Exception" ex stacktrace(catch_backtrace())
  #end
end




