export MeasurementController, MeasurementControllerParams, measurement, MeasState, asyncMeasurement

abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasTyp(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

mutable struct FrameAverageBuffer
  buffer::Array{Float32, 4}
  setIndex::Int
end
FrameAverageBuffer(samples, channels, periods, avgFrames) = FrameAverageBuffer(zeros(Float32, samples, channels, periods, avgFrames), 1)

mutable struct MeasState
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


Base.@kwdef mutable struct MeasurementControllerParams <: DeviceParams
    producerThreadID::Int32 = 2
    consumerThreadID::Int32 = 3
    store::Union{String, DatasetStore, Nothing} = nothing
    bgdata::Union{Nothing} = nothing
end

MeasurementControllerParams(dict::Dict) = params_from_dict(MeasurementControllerParams, dict)

Base.@kwdef mutable struct MeasurementController <: VirtualDevice
    deviceID::String
    params::MeasurementControllerParams
    dependencies::Dict{String, Union{Device, Missing}}

    measState::Union{MeasState, Nothing} = nothing 
    producer::Union{Task,Nothing} = nothing
    consumer::Union{Task, Nothing} = nothing
end

function checkDependencies(measCont::MeasurementController)
  try 
    dependency(measCont, AbstractDAQ)
  catch e 
    @error e
    return false
  end
  return true
end

function init(measCont::MeasurementController)
  @info "Initializing measurement controller with ID `$(measCont.deviceID)`."
end

####  Async version  ####
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

MeasState() = MeasState(0, 0, 1, false, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, false, "", zeros(Float64,0,0))

function cancel(calibState::MeasState)
  close(calibState.channel)
  measState.cancelled = true
  measState.consumed = true
end

function asyncMeasurement(measController::MeasurementController, sequence=Sequence)
  daq = dependency(measController, AbstractDAQ)
  measState = prepareAsyncMeasurement(daq, sequence)
  measController.measState = measState
  measController.producer = @tspawnat measController.params.producerThreadID asyncProducer(measState.channel, measController, sequence)  
  bind(measState.channel, measController.producer)
  measController.consumer = @tspawnat measController.params.consumerThreadID asyncConsumer(measState.channel, measController)
  return measController.producer, measController.consumer, measState
end

function prepareAsyncMeasurement(daq::AbstractDAQ, sequence::Sequence)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  frameAverage = acqNumFrameAverages(sequence)
  setup(daq, sequence)

  # Prepare buffering structures
  @info "Allocating buffer for $numFrames frames"
  # TODO implement properly with only RxMeasurementChannels
  buffer = zeros(Float32,rxNumSamplingPoints, length(rxChannels(sequence)),numPeriods,numFrames)
  #buffer = zeros(Float32,rxNumSamplingPoints,numRxChannelsMeasurement(daq),numPeriods,numFrames)
  avgBuffer = nothing
  if frameAverage > 1
    avgBuffer = FrameAverageBuffer(zeros(Float32, frameAverageBufferSize(daq, frameAverage)), 1)
  end
  channel = Channel{channelType(daq)}(32)

  # Prepare measState
  measState = MeasState(numFrames, 0, 1, false, nothing, AsyncBuffer(daq), buffer, avgBuffer, false, "", zeros(Float64,0,0))
  measState.channel = channel
  return measState
end

function asyncProducer(channel::Channel, measController::MeasurementController, sequence::Sequence)
  su = nothing 
  if hasDependency(measController, SurveillanceUnit)
    su = dependency(measController, SurveillanceUnit)
    #enableACPower(su, ...) # TODO
  end
  robot = nothing
  if hasDependency(measController, Robot)
    robot = dependeny(measController, Robot)
    setEnabled(robot, false)
  end

  daq = dependency(measController, AbstractDAQ)
  asyncProducer(channel, daq, sequence)
  #disconnect(daq)
  
  if !isnothing(su)
    #disableACPower(su, scanner)
  end
  if !isnothing(robot)
    setEnabled(robot, true)
  end
end

function asyncConsumer(channel::Channel, measController::MeasurementController)
  daq = dependency(measController, AbstractDAQ)
  measState = measController.measState
  innerAsyncConsumer(channel, measState, daq)

  # TODO calibTemperatures is not filled in asyncVersion yet, would need own innerAsyncConsumer
  #if length(measState.temperatures) > 0
  #  params["calibTemperatures"] = measState.temperatures
  #end

  #if !isnothing(measController.params.store)
  #  @info "Storing result"
  #  measState.filename = saveasMDF(measController.params.store, daq, measState.buffer, ..., bgdata=bgdata)
  #end
end

function innerAsyncConsumer(channel::Channel, measState::MeasState, daq::AbstractDAQ)
  # Consumer must not invoke SCPI commands as the server is busy with pipeline
  @info "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(measState.asyncBuffer, chunk)
      updateFrameBuffer!(measState, daq)
    end
    sleep(0.001)
  end
  @info "Consumer end"
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

function storeAsyncMeasurementResult(store, daq::AbstractDAQ, data, params; bgdata=nothing)
  return saveasMDF(store, daq, data, params; bgdata=bgdata) # auxData?
end


#### Sync version ####
function measurement(measController::MeasurementController, sequence::Sequence)
  producer, consumer, measState = asyncMeasurement(measController, sequence)
  result = nothing
  try
    wait(consumer)
  catch e
    if isa(e, TaskFailedException)
      @error e.task.exception
      result = nothing
    end
  end

  # Check tasks
  if Base.istaskfailed(producer) || Base.istaskfailed(consumer)
    @warn "Inner async measurement failed"
    result = nothing
  else
    result = measState.buffer
  end
  return result
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
