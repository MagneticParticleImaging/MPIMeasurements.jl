export measurement, asyncMeasurement, measurementCont, measurementRepeatability,
       MeasState

function measurement(daq::AbstractDAQ, params_::Dict;
                     kargs... )
  updateParams!(daq, params_)
  measurement_(daq; kargs...)
end

function measurement_(daq::AbstractDAQ)

  startTxAndControl(daq)

  # Prepare acqSeq
  currFr = enableSequence(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
                         daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

  framePeriod = daq.params.acqNumFrameAverages*daq.params.acqNumPeriodsPerFrame*daq.params.dfCycle
  @time uMeas, uRef = readData(daq, daq.params.acqNumFrames*daq.params.acqNumFrameAverages, currFr)
  @info "It should take $(daq.params.acqNumFrames*daq.params.acqNumFrameAverages*framePeriod)"
  sleep(daq.params.ffRampUpTime)    ### This should be analog to asyncMeasurementInner
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
  subject = ""

  newStudy = Study(store, name; subject=subject, date=date)
  expNum = getNewExperimentNum(newStudy)

  #daq["studyName"] = params["studyName"]
  params["experimentNumber"] = expNum

  filename = joinpath(path(newStudy), string(expNum)*".mdf")

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
abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <:AsyncMeasTyp end
struct RegularAsyncMeas <:AsyncMeasTyp end
asyncMeasTyp(daq::AbstractDAQ) = daq.params.acqNumFrameAverages > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

mutable struct FrameAverageBuffer
  buffer::Array{Float32, 4}
  setIndex::Int
end
FrameAverageBuffer(samples, channels, periods, avgFrames) = FrameAverageBuffer(zeros(Float32, samples, channels, periods, avgFrames), 1)

mutable struct MeasState
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  numFrames::Int
  currFrame::Int
  nextFrame::Int
  cancelled::Bool
  channel::Union{Channel, Nothing}
  asyncBuffer::AsyncBuffer
  buffer::Array{Float32,4}
  avgBuffer::Union{FrameAverageBuffer, Nothing}
  consumed::Bool
  filename::String
  temperatures::Matrix{Float64}
end

function addFramesToAvg(avgBuffer::FrameAverageBuffer, frames::Array{Float32, 4})
  #setIndex - 1 = how many frames were written to the buffer

  # Compute how many frames there will be
  avgSize = size(avgBuffer.buffer)
  resultFrames = div(avgBuffer.setIndex - 1 + size(frames, 4), avgSize[4])

  result = nothing
  if resultFrames > 0
    result = zeros(Float32, avgSize[1], avgSize[2], avgSize[3], resultFrames)
  end

  setResult = 1
  fr = 1 
  while fr <= size(frames, 4)
    # How many left vs How many can fit into avgBuffer
    fit = min(size(frames, 4) - fr, avgSize[4] - avgBuffer.setIndex)
    
    # Insert into buffer
    toFrames = fr + fit 
    toAvg = avgBuffer.setIndex + fit 
    avgBuffer.buffer[:, :, :, avgBuffer.setIndex:toAvg] = frames[:, :, :, fr:toFrames]
    avgBuffer.setIndex += length(avgBuffer.setIndex:toAvg)
    fr = toFrames + 1
    
    # Average and add to result
    if avgBuffer.setIndex - 1 == avgSize[4]
      avgFrame = mean(avgBuffer.buffer, dims=4)[:,:,:,:]
      result[:, :, :, setResult] = avgFrame
      setResult += 1
      avgBuffer.setIndex = 1    
    end
  end

  return result
end

MeasState() = MeasState(nothing, nothing, 0, 0, 1, false, nothing, nothing, zeros(Float64,0,0,0,0), nothing, false, "", zeros(Float64,0,0))

function cancel(calibState::MeasState)
  close(calibState.channe)
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

  # Prepare buffering structures
  @info "Allocating buffer for $numFrames frames"
  buffer = zeros(Float32,rxNumSamplingPoints,numRxChannels(daq),numPeriods,numFrames)
  avgBuffer = nothing
  if daq.params.acqNumFrameAverages > 1
    avgBuffer = FrameAverageBuffer(zeros(Float32, frameAverageBufferSize(daq, daq.params.acqNumFrameAverages)), 1)
  end
  channel = Channel{channelType(daq)}(32)

  # Start Producer, consumer tasks
  measState = MeasState(nothing, nothing, numFrames, 0, 1, false, nothing, AsyncBuffer(daq), buffer, avgBuffer, false, "", zeros(Float64,0,0))
  measState.channel = channel
  measState.producer = @tspawnat 2 asyncProducer(measState.channel, scanner, numFrames * daq.params.acqNumFrameAverages)
  bind(measState.channel, measState.producer)
  measState.consumer = @tspawnat 3 asyncConsumer(measState.channel, measState, scanner, store, params, bgdata)

  return measState
end

function asyncProducer(channel::Channel, scanner::MPIScanner, numFrames)
  su = getSurveillanceUnit(scanner)
  daq = getDAQ(scanner)
  #tempSensor = getTemperatureSensor(scanner)

  #if tempSensor != nothing
  #  measState.temperatures = zeros(Float32, numChannels(tempSensor), daq.params.acqNumFrames)
  #end
  setEnabled(getRobot(scanner), false)
  enableACPower(su, scanner)
  asyncProducer(channel, daq, numFrames)
  disableACPower(su, scanner)
  disconnect(daq)
  setEnabled(getRobot(scanner), true)
end

function asyncConsumer(channel::Channel, measState::MeasState, scanner::MPIScanner, store::DatasetStore, params::Dict, bgdata=nothing)
  # Consumer must not invoke SCPI commands as the server is busy with pipeline
  @info "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(measState.asyncBuffer, chunk)
      updateFrameBuffer!(measState, getDAQ(scanner))
    end
    sleep(0.001)
  end
  @info "Consumer end"

  if length(measState.temperatures) > 0
    params["calibTemperatures"] = measState.temperatures
  end

  measState.filename = saveasMDF(store, getDAQ(scanner), measState.buffer, params; bgdata=bgdata) #, auxData=auxData)

end

function updateFrameBuffer!(measState::MeasState, daq::AbstractDAQ)
  uMeas, uRef = retrieveMeasAndRef!(measState.asyncBuffer, daq)
  if !isnothing(uMeas)
    isNewFrameAvailable, fr = handleNewFrame(asyncMeasTyp(daq), measState, uMeas)
    if isNewFrameAvailable && fr > 0
      measState.currFrame = fr 
      measState.consumed = false
    end
  end
end

function handleNewFrame(::RegularAsyncMeas, measState::MeasState, uMeas)
  isNewFrameAvailable = false

  fr = addFramesFrom(measState, uMeas)
  isNewFrameAvailable = true

  return isNewFrameAvailable, fr
end

function handleNewFrame(::FrameAveragedAsyncMeas, measState::MeasState, uMeas)
  isNewFrameAvailable = false

  fr = 0
  framesAvg = addFramesToAvg(measState.avgBuffer, uMeas)
  if !isnothing(framesAvg)
    fr = addFramesFrom(measState, framesAvg)
    isNewFrameAvailable = true
  end

  return isNewFrameAvailable, fr
end

function addFramesFrom(measState::MeasState, frames::Array{Float32, 4})
  fr = measState.nextFrame
  to = fr + size(frames, 4) - 1
  limit = size(measState.buffer, 4)
  @info "Add frames $fr to $to to framebuffer with $limit size"
  if to <= limit
    measState.buffer[:,:,:,fr:to] = frames
    measState.nextFrame = to + 1
    return fr
  end
  return -1 
end

function asyncMeasurementInner(measState::MeasState, scanner::MPIScanner,
                                 store::DatasetStore, params::Dict, bgdata=nothing)
    su = getSurveillanceUnit(scanner)
    daq = getDAQ(scanner)
    #tempSensor = getTemperatureSensor(scanner)

    #if tempSensor != nothing
    #  measState.temperatures = zeros(Float32, numChannels(tempSensor), daq.params.acqNumFrames)
    #end

    setEnabled(getRobot(scanner), false)
    enableACPower(su, scanner)

    startTxAndControl(daq)

    currFr = enableSequence(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
                           daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

    chunkTime = 2.0 #seconds
    framePeriod = daq.params.acqNumFrameAverages*daq.params.acqNumPeriodsPerFrame *
                  daq.params.dfCycle
    chunk = min(daq.params.acqNumFrames,max(1,round(Int, chunkTime/framePeriod)))
    
    fr = 1
    while fr <= daq.params.acqNumFrames
      to = min(fr+chunk-1,daq.params.acqNumFrames) 

      #if tempSensor != nothing
      #  for c = 1:numChannels(tempSensor)
      #      measState.temperatures[c,fr] = getTemperature(tempSensor, c)
      #  end
      #end
      @info "Measuring frame $fr to $to"
      @time uMeas, uRef = readData(daq, daq.params.acqNumFrameAverages*(length(fr:to)),
                                  currFr + (fr-1)*daq.params.acqNumFrameAverages)
      @info "It should take $(daq.params.acqNumFrameAverages*(length(fr:to))*framePeriod)"
      s = size(uMeas)
      @info s
      if daq.params.acqNumFrameAverages == 1
        measState.buffer[:,:,:,fr:to] = uMeas
      else
        tmp = reshape(uMeas, s[1], s[2], s[3], daq.params.acqNumFrameAverages, :) # bug?
        measState.buffer[:,:,:,fr:to] = dropdims(mean(uMeas, dims=4),dims=4)
        #
        #I think was meant to be this:
        temp = reshape(uMeas, s[1], s[2], s[3],
                daq.params.acqNumFrames,daq.params.acqNumFrameAverages)
        uMeasAv = mean(temp, dims=5)[:,:,:,:,1]
        #...need to wait for enough frames to be acquired for averaging in new async
        #
      end
      measState.currFrame = fr
      measState.consumed = false
      #sleep(0.01)
      #yield()
      fr += chunk

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
end




