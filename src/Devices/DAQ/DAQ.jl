import Base: setindex!, getindex

export AbstractDAQ, DAQParams, SinkImpedance, DAQChannelParams, DAQFeedback, DAQTxChannelParams, DAQRxChannelParams,
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

abstract type DAQChannelParams end

Base.@kwdef struct DAQFeedback
  channelID::AbstractString
  calibration::Union{typeof(1.0u"T/V"), Nothing} = nothing
end

Base.@kwdef struct DAQTxChannelParams <: DAQChannelParams
  channelIdx::Int64
  limitPeak::typeof(1.0u"V")
  sinkImpedance::SinkImpedance = SINK_HIGH
  allowedWaveforms::Vector{Waveform} = [WAVEFORM_SINE]
  feedback::Union{DAQFeedback, Nothing} = nothing
  calibration::Union{typeof(1.0u"V/T"), Nothing} = nothing
end

Base.@kwdef struct DAQRxChannelParams <: DAQChannelParams
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
  splattingDict[:channels] = createDAQChannels(channelDict)

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

@mustimplement setup(daq::AbstractDAQ, sequence::Sequence)
@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, correctionAmp, correctionPhase; convoluted=true)
#@mustimplement trigger(daq::AbstractDAQ)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, startFrame, numFrames, numBlockAverages)
@mustimplement readDataPeriods(daq::AbstractDAQ, startPeriod, numPeriods)
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
function getDAQ(scanner::MPIScanner)
  daqs = getDAQs(scanner)
  if length(daqs) > 1
    error("The scanner has more than one DAQ device. Therefore, a single DAQ cannot be retrieved unambiguously.")
  else
    return daqs[1]
  end
end

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

include("RedPitayaDAQ.jl")
include("DummyDAQ.jl")
include("SimpleSimulatedDAQ.jl")