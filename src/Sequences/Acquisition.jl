export RxChannel, AcquisitionSettings

"Receive channel reference that should be included in the acquisition."
Base.@kwdef struct RxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
end

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
  "Flag for background measurement"
  isBackground::Bool = false
end