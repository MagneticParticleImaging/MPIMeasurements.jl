export RxChannel, AcquisitionSettings

"Receive channel reference that should be included in the acquisition."
Base.@kwdef struct RxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
end

id(channel::RxChannel) = channel.id

toDictValue(channel::RxChannel) = id(channel)

"Settings for acquiring the sequence."
Base.@kwdef mutable struct AcquisitionSettings
  "Receive channels that are used in the sequence."
  channels::Vector{RxChannel}
  "Bandwidth (half the sample rate) of the receiver. In DAQs which decimate the data,
  this also determines the decimation. Note: this is currently a
  scalar since the MDF does not allow for multiple sampling rates yet."
  bandwidth::typeof(1.0u"Hz")
  "Number of periods within a frame."
  numPeriodsPerFrame::Integer = 1
  "Number of frames to acquire"
  numFrames::Integer = 1
  "Number of block averages per period."
  numAverages::Integer = 1
  "Number of frames to average blockwise."
  numFrameAverages::Integer = 1
end

# Indexing Interface
length(acq::AcquisitionSettings) = length(rxChannels(acq))
function getindex(acq::AcquisitionSettings, index::Integer)
  1 <= index <= length(acq) || throw(BoundsError(rxChannels(acq), index))
  return rxChannels(acq)[index]
end
function getindex(acq::AcquisitionSettings, index::String)
  for channel in acq
    if id(channel) == index
      return channel
    end
  end
  throw(KeyError(index))
end
setindex!(acq::AcquisitionSettings, rxChannel::RxChannel, i::Integer) = rxChannels(acq)[i] = rxChannel
firstindex(acq::AcquisitionSettings) = start_(acq)
lastindex(acq::AcquisitionSettings) = length(acq)
keys(acq::AcquisitionSettings) = map(id, acq)
haskey(acq::AcquisitionSettings, key) = in(key, keys(acq))


# Iterable Interface
start_(acq::AcquisitionSettings) = 1
next_(acq::AcquisitionSettings,state) = (acq[state],state+1)
done_(acq::AcquisitionSettings,state) = state > length(acq)
iterate(acq::AcquisitionSettings, s=start_(acq)) = done_(acq, s) ? nothing : next_(acq, s)

push!(acq::AcquisitionSettings, rxChannel::RxChannel) = push!(rxChannels(acq), rxChannel)
pop!(acq::AcquisitionSettings) = pop!(rxChannels(acq))
empty!(acq::AcquisitionSettings) = empty!(rxChannels(acq))
deleteat!(acq::AcquisitionSettings, i) = deleteat!(rxChannels(acq), i)
function delete!(acq::AcquisitionSettings, index::String)
  idx = findfirst(isequal(index), map(id, acq))
  isnothing(idx) ? throw(KeyError(index)) : deleteat!(acq, idx)
end

acqNumFrames(acq::AcquisitionSettings) = acq.numFrames
acqNumFrames(acq::AcquisitionSettings, val) = acq.numFrames = val

export acqNumAverages
acqNumAverages(acq::AcquisitionSettings) = acq.numAverages
acqNumAverages(acq::AcquisitionSettings, val) = acq.numAverages = val

export acqNumFrameAverages
acqNumFrameAverages(acq::AcquisitionSettings) = acq.numFrameAverages
acqNumFrameAverages(acq::AcquisitionSettings, val) = acq.numFrameAverages = val

export isBackground
isBackground(acq::AcquisitionSettings) = acq.isBackground
isBackground(acq::AcquisitionSettings, val) = acq.isBackground = val

export rxBandwidth
rxBandwidth(acq::AcquisitionSettings) = acq.bandwidth

export rxChannels
rxChannels(acq::AcquisitionSettings) = acq.channels

export rxSamplingRate
rxSamplingRate(acq::AcquisitionSettings) = 2 * rxBandwidth(acq)

export rxNumChannels
rxNumChannels(acq::AcquisitionSettings) = length(rxChannels(acq))
