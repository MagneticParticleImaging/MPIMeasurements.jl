import Base: setindex!, getindex

export AbstractDAQ, DAQParams, SinkImpedance, SINK_FIFTY_OHM, SINK_HIGH, DAQTxChannelSettings, DAQChannelParams, DAQFeedback, DAQTxChannelParams, DAQRxChannelParams,
       createDAQChannels, createDAQParams, startTx, stopTx, setTxParams, readData,
       numRxChannelsTotal, numTxChannelsTotal, numRxChannelsActive, numTxChannelsActive,
       currentPeriod, getDAQ, getDAQs,
       channelIdx, limitPeak, sinkImpedance, allowedWaveforms, isWaveformAllowed,
       feedbackChannelID, feedbackCalibration, calibration

abstract type AbstractDAQ <: Device end
abstract type DAQParams <: DeviceParams end

@enum SinkImpedance begin
  SINK_FIFTY_OHM
  SINK_HIGH
end

@enum TxValueRange begin
  #POSITIVE
  #NEGATIVE
  BOTH
  HBRIDGE
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

Base.@kwdef mutable struct DAQFeedback
  channelID::AbstractString
  calibration::Union{TransferFunction, String, Nothing} = nothing
end

Base.@kwdef struct DAQHBridge{N}
  channelID::Union{String, Vector{String}}
  manual::Bool = false
  deadTime::typeof(1.0u"s") = 0.0u"s"
  level::Matrix{typeof(1.0u"V")} # Can this be simplified by a convention for h-bridges?
end
negativeLevel(bridge::DAQHBridge) = bridge.level[:, 1]
positiveLevel(bridge::DAQHBridge) = bridge.level[:, 2]
level(bridge::DAQHBridge, x::Number) = signbit(x) ? negativeLevel(bridge) : positiveLevel(bridge)
manual(bridge::DAQHBridge) = bridge.manual
deadTime(bridge::DAQHBridge) = bridge.deadTime
id(bridge::DAQHBridge) = bridge.channelID

function createDAQChannels(::Type{DAQHBridge}, dict::Dict{String, Any})
  splattingDict = Dict{Symbol, Any}()
  splattingDict[:channelID] = dict["channelID"] isa Vector ? dict["channelID"] : [dict["channelID"]]
  N = length(splattingDict[:channelID])
  splattingDict[:level] = reshape(uparse.(dict["level"]), N, :)

  if haskey(dict, "manual")
    splattingDict[:manual] = dict["manual"]
  end

  if haskey(dict, "deadTime")
    splattingDict[:deadTime] = uparse(dict["deadTime"])
  end
  return DAQHBridge{N}(;splattingDict...)
end

Base.@kwdef mutable struct DAQTxChannelParams <: TxChannelParams
  channelIdx::Int64
  limitPeak::typeof(1.0u"V")
  limitSlewRate::typeof(1.0u"V/s") = 1000.0u"V/µs" # default is basically no limit
  sinkImpedance::SinkImpedance = SINK_HIGH
  allowedWaveforms::Vector{Waveform} = [WAVEFORM_SINE]
  feedback::Union{DAQFeedback, Nothing} = nothing
  calibration::Union{TransferFunction, String, Nothing} = nothing
end

Base.@kwdef struct DAQRxChannelParams <: RxChannelParams
  channelIdx::Int64
end

function createDAQChannel(::Type{DAQTxChannelParams}, dict::Dict{String,Any})
  splattingDict = Dict{Symbol, Any}()
  splattingDict[:channelIdx] = dict["channel"]
  splattingDict[:limitPeak] = uparse(dict["limitPeak"])

  if haskey(dict, "limitSlewRate")
    splattingDict[:limitSlewRate] = uparse(dict["limitSlewRate"])
  end

  if haskey(dict, "sinkImpedance")
    splattingDict[:sinkImpedance] = dict["sinkImpedance"] == "FIFTY_OHM" ? SINK_FIFTY_OHM : SINK_HIGH
  end

  if haskey(dict, "allowedWaveforms")
    splattingDict[:allowedWaveforms] = toWaveform.(dict["allowedWaveforms"])
  end

  if haskey(dict, "feedback")
    channelID = dict["feedback"]["channelID"]
    calibration_tf = parse_into_tf(dict["feedback"]["calibration"])
    splattingDict[:feedback] = DAQFeedback(channelID=channelID, calibration=calibration_tf)
  end

  if haskey(dict, "calibration")
    splattingDict[:calibration] = parse_into_tf(dict["calibration"])
  end

  return DAQTxChannelParams(;splattingDict...)
end

function parse_into_tf(value::String)
  if occursin(".h5", value) # case 1: filename to transfer function, the TF will be read the first time calibration() is called, (done in _init(), to prevent delays while using the device)
    calibration_tf = value
  else # case 2: single value, extended into transfer function with no frequency dependency
    calibration_value = uparse(value)
    calibration_tf = TransferFunction([0,10e6],ComplexF64[ustrip(calibration_value), ustrip(calibration_value)], units=[unit(calibration_value)])
  end
  return calibration_tf
end

createDAQChannel(::Type{DAQRxChannelParams}, value) = DAQRxChannelParams(channelIdx=value["channel"])

"Create DAQ channel description from device dict part."
function createDAQChannels(dict::Dict{String, Any})
  channels = Dict{String, DAQChannelParams}()
  for (key, value) in dict
    if value["type"] == "tx"
      channels[key] = createDAQChannel(DAQTxChannelParams, value)
    elseif value["type"] == "rx"
      channels[key] = createDAQChannel(DAQRxChannelParams, value)
    elseif value["type"] == "txSlow"
      channels[key] = createDAQChannel(RedPitayaLUTChannelParams, value)
    end
  end

  return channels
end

# Generic case
function createDAQChannels(::Type{T}, dict::Dict{String, Any}) where {T <: DAQParams}
  return createDAQChannels(dict)
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function createDAQParams(DAQType::Type{T}, dict::Dict{String, Any}) where {T <: DAQParams}
  # Extract all main section fields which means excluding `channels`
  mainSectionFields = [string(field) for field in fieldnames(DAQType) if field != :channels]

  # Split between main section fields and channels, which are dictionaries
  channelDict = Dict{String, Any}()
  mainDict = Dict{String, Any}()
  for (key, value) in dict
    if value isa Dict && !(key in mainSectionFields)
      channelDict[key] = value
    else
      mainDict[key] = value
    end
  end

  splattingDict = dict_to_splatting(mainDict)
  splattingDict[:channels] = createDAQChannels(DAQType, channelDict)
  # TODO: check if DAQ type can actually support all types of channels
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
@mustimplement endSequence(daq::AbstractDAQ, endValue) # Sequence can be ended outside of producer
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
function feedbackCalibration(daq::AbstractDAQ, channelID::AbstractString)
  if !isnothing(feedback(daq, channelID)) && isa(feedback(daq, channelID).calibration, String) # if TF has not been loaded yet, load the h5 file
    feedback(daq, channelID).calibration = TransferFunction(joinpath(configDir(daq),"TransferFunctions",feedback(daq, channelID).calibration))
  else
    if !isnothing(feedback(daq, channelID))
      return feedback(daq, channelID).calibration
    else 
      return nothing
    end
  end
end
function calibration(daq::AbstractDAQ, channelID::AbstractString)
  if isa(channel(daq, channelID).calibration, String) # if TF has not been loaded yet, load the h5 file
    channel(daq, channelID).calibration = TransferFunction(joinpath(configDir(daq),"TransferFunctions",channel(daq, channelID).calibration))
  else
    return channel(daq, channelID).calibration 
  end
end

function calibration(daq::AbstractDAQ, channelID::AbstractString, frequency::Real)
  cal = calibration(daq, channelID)
  if cal isa TransferFunction
    return cal(frequency)
  else
    @warn "You requested a calibration for a specific frequency $frequency but the channel $channelID has no frequency dependent calibration value"
    return cal
  end
end

export applyForwardCalibration!, applyForwardCalibration

function applyForwardCalibration(seq::Sequence, device::Device)
  seqCopy = deepcopy(seq)
  applyForwardCalibration!(seqCopy, device)
  return seqCopy
end

function applyForwardCalibration!(seq::Sequence, device::Device)

  for channel in periodicElectricalTxChannels(seq) 
    off = offset(channel)
    if dimension(off) != dimension(1.0u"V")
      isnothing(calibration(device, id(channel))) && throw(ScannerConfigurationError("An offset value in channel $(id(channel)) requires calibration but no calibration is configured on the DAQ channel!"))
      offsetVolts = off*abs(calibration(device, id(channel), 0)) # use DC value for offsets
      offset!(channel, uconvert(u"V",offsetVolts))
    end

    for comp in components(channel)
      amp = amplitude(comp)
      pha = phase(comp)
      if dimension(amp) != dimension(1.0u"V")
        isnothing(calibration(device, id(channel))) && throw(ScannerConfigurationError("An amplitude value in channel $(id(channel)) requires calibration but no calibration is configured on the DAQ channel!"))
        f_comp = ustrip(u"Hz", txBaseFrequency(seq)) / divider(comp)
        complex_comp = (amp*exp(im*pha)) * calibration(device, id(channel), f_comp)
        amplitude!(comp, uconvert(u"V",abs(complex_comp)))
        phase!(comp, angle(complex_comp)u"rad")
        if comp isa ArbitraryElectricalComponent
          N = length(values(comp))
          f_awg = rfftfreq(N, f_comp*N)
          calib = calibration(device, id(channel), f_awg) ./ (abs.(calibration(device, id(channel), f_comp))*exp.(im*2*pi*range(0,length(f_awg)-1).*angle(calibration(device, id(channel),f_comp)))) # since amplitude and phase are already calibrated for the base frequency, here we need to remove that factor
          values!(comp, irfft(rfft(values(comp)).*calib, N))
        end
      end
    end
  end
  
  for lutChannel in acyclicElectricalTxChannels(seq)
    if lutChannel isa StepwiseElectricalChannel
      values = lutChannel.values
      if dimension(values[1]) != dimension(1.0u"V")
        isnothing(calibration(device, id(lutChannel))) && throw(ScannerConfigurationError("A value in channel $(id(lutChannel)) requires calibration but no calibration is configured on the DAQ channel!"))
        values = values.*calibration(device, id(lutChannel))
        lutChannel.values = values
      end
    elseif lutChannel isa ContinuousElectricalChannel
      amp = lutChannel.amplitude
      off = lutChannel.offset
      if dimension(amp) != dimension(1.0u"V")
        isnothing(calibration(device, id(lutChannel))) && throw(ScannerConfigurationError("An amplitude value in channel $(id(lutChannel)) requires calibration but no calibration is configured on the DAQ channel!"))
        amp = amp*calibration(device, id(lutChannel))
        lutChannel.amplitude = amp
      end
      if dimension(off) != dimension(1.0u"V")
        isnothing(calibration(device, id(lutChannel))) && throw(ScannerConfigurationError("An offset value in channel $(id(lutChannel)) requires calibration but no calibration is configured on the DAQ channel!"))
        off = off*calibration(device, id(lutChannel))
        lutChannel.offset = off
      end
    end
  end
  
  nothing
end



#### Measurement Related Functions ####
@mustimplement startProducer(channel::Channel, daq::AbstractDAQ, numFrames; isControlStep)
@mustimplement channelType(daq::AbstractDAQ) # What is written to the channel
@mustimplement AsyncBuffer(buffer::StorageBuffer, daq::AbstractDAQ) # Buffer structure that contains channel elements
@mustimplement push!(buffer::AsyncBuffer, chunk) # Adds channel element to buffer
@mustimplement retrieveMeasAndRef!(buffer::AsyncBuffer, daq::AbstractDAQ) # Retrieve all available measurement and reference frames from the buffer

function asyncProducer(channel::Channel, daq::AbstractDAQ, sequence::Sequence; isControlStep=false)
  numFrames = acqNumFrames(sequence) * acqNumFrameAverages(sequence)
  endSample = startProducer(channel, daq, numFrames, isControlStep=isControlStep)
  return endSample
end

include("RedPitayaDAQ.jl")
include("DummyDAQ.jl")
include("SimpleSimulatedDAQ.jl")