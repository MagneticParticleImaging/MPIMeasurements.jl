import Base: setindex!, getindex

export AbstractDAQ, DAQParams, SinkImpedance, SINK_FIFTY_OHM, SINK_HIGH, DAQTxChannelSettings, DAQChannelParams, DAQFeedback, DAQTxChannelParams, DAQRxChannelParams,
       createDAQChannels, createDAQParams, startTx, stopTx, setTxParams, currentFrame, readData,
       numRxChannelsTotal, numTxChannelsTotal, numRxChannelsActive, numTxChannelsActive,
       DAQ, readDataPeriod, currentPeriod, getDAQ, getDAQs,
       channelIdx, limitPeak, sinkImpedance, allowedWaveforms, isWaveformAllowed,
       feedbackChannelID, feedbackCalibration, calibration

abstract type AbstractDAQ <: Device end
abstract type DAQParams <: DeviceParams end

@enum SinkImpedance begin
  SINK_FIFTY_OHM
  SINK_HIGH
end

struct DAQTxChannelSettings
  "Applied channel voltage. Dimensions are (components, channels, periods)."
  amplitudes::Array{typeof(1.0u"V"), 3}
  "Applied channel phase. Dimensions are (components, channels, periods)."
  phases::Array{typeof(1.0u"rad"), 3}
  "Minimum time for changing phase and amplitude to the given settings"
  changeTime::typeof(1.0u"s")
  "Channel mapping from ID to index."
  mapping::Dict{String, Integer}

  function DAQTxChannelSettings(amplitudes, phases, changeTime, mapping)
    if size(amplitudes) != size(phases) || size(amplitudes, 2) != length(mapping)
      error("The sizes of `phases` and `amplitudes` as well as the number of channels have to match.")
    end

    if changeTime < 0.0u"s"
      error("The change time can only be positive.")
    end

    return new(amplitudes, phases, changeTime, mapping)
  end
end

numChannels(settings::DAQTxChannelSettings) = size(settings.amplitudes, 2)
channelIDs(settings::DAQTxChannelSettings) = keys(settings.mapping)
amplitudes(settings::DAQTxChannelSettings) = settings.amplitudes
amplitudes(settings::DAQTxChannelSettings, channelID::String) = settings.amplitudes[:, mapping[channelID], :]
phases(settings::DAQTxChannelSettings) = settings.phases
phases(settings::DAQTxChannelSettings, channelID::String) = settings.phases[:, mapping[channelID], :]
changeTime(settings::DAQTxChannelSettings) = settings.changeTime

abstract type DAQChannelParams end
abstract type TxChannelParams <: DAQChannelParams end
abstract type RxChannelParams <: DAQChannelParams end

Base.@kwdef struct DAQFeedback
  channelID::AbstractString
  calibration::Union{typeof(1.0u"T/V"), Nothing} = nothing
end

Base.@kwdef struct DAQTxChannelParams <: TxChannelParams
  channelIdx::Int64
  limitPeak::typeof(1.0u"V")
  sinkImpedance::SinkImpedance = SINK_HIGH
  allowedWaveforms::Vector{Waveform} = [WAVEFORM_SINE]
  feedback::Union{DAQFeedback, Nothing} = nothing
  calibration::Union{typeof(1.0u"V/T"), Nothing} = nothing
end

Base.@kwdef struct DAQRxChannelParams <: RxChannelParams
  channelIdx::Int64
end

"Create DAQ channel description from device dict part."
function createDAQChannels(dict::Dict{String, Any})
  channels = Dict{String, DAQChannelParams}()
  for (key, value) in dict
    splattingDict = Dict{Symbol, Any}()
    if value["type"] == "tx"
      splattingDict[:channelIdx] = value["channel"]
      splattingDict[:limitPeak] = uparse(value["limitPeak"])

      if haskey(value, "sinkImpedance")
        splattingDict[:sinkImpedance] = value["sinkImpedance"] == "FIFTY_OHM" ? SINK_FIFTY_OHM : SINK_HIGH
      end

      if haskey(value, "allowedWaveforms")
        splattingDict[:allowedWaveforms] = toWaveform.(value["allowedWaveforms"])
      end

      if haskey(value, "feedback")
        channelID=value["feedback"]["channelID"]
        calibration=uparse(value["feedback"]["calibration"])

        splattingDict[:feedback] = DAQFeedback(channelID=channelID, calibration=calibration)
      end

      if haskey(value, "calibration")
        splattingDict[:calibration] = uparse.(value["calibration"])
      end

      channels[key] = DAQTxChannelParams(;splattingDict...)
    elseif value["type"] == "rx"
      channels[key] = DAQRxChannelParams(channelIdx=value["channel"])
    end
  end

  return channels
end

# Generic case
function createDAQChannels(::Type{T}, dict::Dict{String, Any}) where {T <: DAQParams}
  return createDAQChannels(dict)
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function createDAQParams(DAQType::DataType, dict::Dict{String, Any})
  @assert DAQType <: DAQParams "The supplied type `$type` cannot be used for creating DAQ params, since it does not inherit from `DAQParams`."
  
  # Extract all main section fields which means excluding `channels`
  mainSectionFields = [string(field) for field in fieldnames(DAQType) if field != :channels]

  # Split between main section fields and channels, which are dictionaries
  channelDict = Dict{String, Any}()
  for (key, value) in dict
    if value isa Dict && !(key in mainSectionFields)
      channelDict[key] = value
      
      # Remove key in order to process the rest with the standard function
      delete!(dict, key)
    end
  end

  splattingDict = dict_to_splatting(dict)
  splattingDict[:channels] = createDAQChannels(DAQType, channelDict)

  try
    return DAQType(;splattingDict...)
  catch e
    if e isa UndefKeywordError
      throw(ScannerConfigurationError("The required field `$(e.var)` is missing in your configuration "*
                                      "for a device with the params type `$DAQType`."))
    elseif e isa MethodError
      @warn e.args e.world e.f
      throw(ScannerConfigurationError("A required field is missing in your configuration for a device "*
                                      "with the params type `$DAQType`. Please check "*
                                      "the causing stacktrace."))
    else
      rethrow()
    end
  end
end

#include("Control.jl")
#include("Plotting.jl")
#include("Parameters.jl")

@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, sequence::Sequence)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, startFrame, numFrames)
@mustimplement readDataPeriods(daq::AbstractDAQ, startPeriod, numPeriods)
@mustimplement refToField(daq::AbstractDAQ, d::Int64)

@mustimplement setSequenceParams(daq::AbstractDAQ, sequence::Sequence) # Needs to be able to update seqeuence parameters
@mustimplement prepareSequence(daq::AbstractDAQ, sequence::Sequence) # Sequence can be prepared before started
@mustimplement endSequence(daq::AbstractDAQ) # Sequence can be ended outside of producer
@mustimplement prepareTx(daq::AbstractDAQ, sequence::Sequence; allowControlLoop = true) # Tx can be set outside of producer
# Producer prepares a proper sequence if allowed too, then starts it and writes the resulting chunks to the channel

@mustimplement numTxChannelsTotal(daq::AbstractDAQ)
@mustimplement numRxChannelsTotal(daq::AbstractDAQ)
@mustimplement numTxChannelsActive(daq::AbstractDAQ)
@mustimplement numRxChannelsActive(daq::AbstractDAQ)
@mustimplement numRxChannelsReference(daq::AbstractDAQ)
@mustimplement numRxChannelsMeasurement(daq::AbstractDAQ)
@mustimplement numComponentsMax(daq::AbstractDAQ)
@mustimplement canPostpone(daq::AbstractDAQ)
@mustimplement canConvolute(daq::AbstractDAQ)

getDAQs(scanner::MPIScanner) = getDevices(scanner, AbstractDAQ)
getDAQ(scanner::MPIScanner) = getDevice(scanner, AbstractDAQ)

# function dataConversionFactor(daq::AbstractDAQ) #default
#   factor = zeros(2, numRxChannels(daq))
#   factor[1,:] = 1.0
#   factor[2,:] = 0.0
#   return factor
# end

channel(daq::AbstractDAQ, channelID::AbstractString) = daq.params.channels[channelID]
channelIdx(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).channelIdx
channelIdx(daq::AbstractDAQ, channelIDs::Vector{<:AbstractString}) = [channel(daq, channelID).channelIdx for channelID in channelIDs]
limitPeak(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).limitPeak
sinkImpedance(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).sinkImpedance
allowedWaveforms(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).allowedWaveforms
isWaveformAllowed(daq::AbstractDAQ, channelID::AbstractString, waveform::Waveform) = waveform in allowedWaveforms(daq, channelID)
feedback(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).feedback
feedbackChannelID(daq::AbstractDAQ, channelID::AbstractString) = feedback(daq, channelID).channelID
feedbackCalibration(daq::AbstractDAQ, channelID::AbstractString) = feedback(daq, channelID).calibration
calibration(daq::AbstractDAQ, channelID::AbstractString) = channel(daq, channelID).calibration



#### Measurement Related Functions ####
@mustimplement startProducer(channel::Channel, daq::AbstractDAQ, numFrames)
@mustimplement channelType(daq::AbstractDAQ) # What is written to the channel
@mustimplement AsyncBuffer(daq::AbstractDAQ) # Buffer structure that contains channel elements
@mustimplement updateAsyncBuffer!(buffer::AsyncBuffer, chunk) # Adds channel element to buffer
@mustimplement retrieveMeasAndRef!(buffer::AsyncBuffer, daq::AbstractDAQ) # Retrieve all available measurement and reference frames from the buffer

function asyncProducer(channel::Channel, daq::AbstractDAQ, sequence::Sequence; prepTx = true, prepSeq = true, endSeq = true)
  if prepTx
      prepareTx(daq, sequence)
  end
  if prepSeq
      setSequenceParams(daq, sequence)
      prepareSequence(daq, sequence)
  end
  
  numFrames = acqNumFrames(sequence) * acqNumFrameAverages(sequence)
  endFrame = startProducer(channel, daq, numFrames)

  if endSeq
      endSequence(daq, endFrame)
  end
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

function updateFrameBuffer!(measState::SequenceMeasState, daq::AbstractDAQ)
  uMeas, uRef = retrieveMeasAndRef!(measState.asyncBuffer, daq)
  @warn "" uMeas size(uMeas)
  if !isnothing(uMeas)
    #isNewFrameAvailable, fr = 
    handleNewFrame(measState.type, measState, uMeas)
    #if isNewFrameAvailable && fr > 0
    #  measState.currFrame = fr 
    #  measState.consumed = false
    #end
  end
end

function handleNewFrame(::RegularAsyncMeas, measState::SequenceMeasState, uMeas)
  isNewFrameAvailable = false

  fr = addFramesFrom(measState, uMeas)
  isNewFrameAvailable = true

  return isNewFrameAvailable, fr
end

function handleNewFrame(::FrameAveragedAsyncMeas, measState::SequenceMeasState, uMeas)
  isNewFrameAvailable = false

  fr = 0
  framesAvg = addFramesToAvg(measState.avgBuffer, uMeas)
  if !isnothing(framesAvg)
    fr = addFramesFrom(measState, framesAvg)
    isNewFrameAvailable = true
  end

  return isNewFrameAvailable, fr
end

function addFramesFrom(measState::SequenceMeasState, frames::Array{Float32, 4})
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

include("RedPitayaDAQ.jl")
include("DummyDAQ.jl")
include("SimpleSimulatedDAQ.jl")

