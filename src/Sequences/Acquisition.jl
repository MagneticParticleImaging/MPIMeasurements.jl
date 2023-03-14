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
