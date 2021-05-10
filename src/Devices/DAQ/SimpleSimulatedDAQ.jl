export SimpleSimulatedDAQ, SimpleSimulatedDAQParams, simulateLangevinInduced

# TODO: Testing 
using Plots

abstract type ChannelParams end

Base.@kwdef struct Feedback
  channelID::AbstractString
  calibration::Union{typeof(1.0u"T/V"), Nothing} = nothing
end

Base.@kwdef struct TxChannelParams <: ChannelParams
  channelIdx::Int64
  limitPeak::typeof(1.0u"V")
  sinkImpedance::SinkImpedance = SINK_HIGH
  allowedWaveforms::Vector{Waveform} = [WAVEFORM_SINE]
  feedback::Union{Feedback, Nothing} = nothing
  calibration::Union{typeof(1.0u"V/T"), Nothing} = nothing
end

Base.@kwdef struct RxChannelParams <: ChannelParams
  channel::Int64
end

Base.@kwdef struct SimpleSimulatedDAQParams <: DeviceParams
  channels::Dict{String, ChannelParams}
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function SimpleSimulatedDAQParams(dict::Dict)
  channels = Dict{String, ChannelParams}()
  for (key, value) in dict
    if value isa Dict
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

          splattingDict[:feedback] = Feedback(channelID=channelID, calibration=calibration)
        end

        if haskey(value, "calibration")
          splattingDict[:calibration] = uparse.(value["calibration"])
        end

        channels[key] = TxChannelParams(;splattingDict...)
      elseif value["type"] == "rx"
        channels[key] = RxChannelParams(channel=value["channel"])
      end
    else
      error("There is an error in the configuration since there should
             only be channel definitions in SimpleSimulatedDAQParams.")
    end
  end
  return SimpleSimulatedDAQParams(channels=channels)
end

Base.@kwdef mutable struct SimpleSimulatedDAQ <: AbstractDAQ
  deviceID::String
  params::SimpleSimulatedDAQParams

  "Base frequency to derive drive field frequencies."
  baseFrequency::Union{typeof(1.0u"Hz"), Missing} = missing
  "Divider of the baseFrequency to determine the drive field frequencies"
  divider::Union{Array{Int64, 2}, Missing} = missing
  "Applied drive field phase."
  phase::Union{Array{typeof(1.0u"rad"), 3}, Missing} = missing
  "Applied drive field voltage."
  amplitude::Union{Array{typeof(1.0u"T"), 3}, Array{typeof(1.0u"V"), 3}, Missing} = missing
  "Waveform type: sine, triangle or custom"
  waveform::Union{Array{Waveform, 2}, Missing} = missing

  txRunning::Bool = false
  
  "Number of periods within a frame."
  numPeriodsPerFrame::Int64 = 1

  rxChanIdx::Vector{Int64} = []
  refChanIdx::Vector{Int64} = []
  rxNumSamplingPoints::Int64 = 0

  currentFrame::Int64 = 1
  currentPeriod::Int64 = 1
end

function setupTx(daq::SimpleSimulatedDAQ, channels::Vector{ElectricalTxChannel}, baseFrequency::typeof(1.0u"Hz"))
  daq.refChanIdx = []
  daq.baseFrequency = baseFrequency

  periodicChannels = [channel for channel in channels if channel isa PeriodicElectricalChannel]
  stepwiseChannels = [channel for channel in channels if channel isa StepwiseElectricalTxChannel]

  if !isempty(stepwiseChannels)
    @warn "The simple simulated DAQ can only process periodic channels. Other channels are ignored."
  end

  if any([length(component.amplitude) > 1 for channel in periodicChannels for component in channel.components])
    error("The simple simulated DAQ cannot work with more than one period in a frame or frequency sweeps yet.")
  end

  # Initialize fields
  numChannels_ = length(channels)
  numComponents_ = length([component for channel in periodicChannels for component in channel.components])
  daq.divider = zeros(Int64, (numComponents_, numChannels_))
  daq.phase = fill(0.0u"rad", (numComponents_, numChannels_, 1))
  daq.amplitude = fill(0.0u"T", (numComponents_, numChannels_, 1))
  daq.waveform = fill(WAVEFORM_SINE, (numComponents_, numChannels_))

  for channel in periodicChannels
    scannerChannel = daq.params.channels[channel.id]
    channelMapping = scannerChannel.channelIdx # Switch to getter?

    # Activate corresponding receive channels
    if !isnothing(scannerChannel.feedback)
      scannerFeedbackChannel = daq.params.channels[scannerChannel.feedback.channelID]
      feedbackChannelMapping = scannerFeedbackChannel.channel # Switch to getter?
      push!(daq.refChanIdx, feedbackChannelMapping)
    end

    componentIndex = 1
    for component in channel.components
      daq.divider[componentIndex, channelMapping, 1] = component.divider
      daq.phase[componentIndex, channelMapping, 1] = component.phase[1] # Only one period is allowed
      daq.waveform[componentIndex, channelMapping] = channel.waveform # TODO: Allow waveform for every component (subtractive fourier synthesis)
      daq.amplitude[componentIndex, channelMapping, 1] = component.amplitude[1]
      componentIndex += 1
    end
  end
end

function setupRx(daq::SimpleSimulatedDAQ, channels::Vector{RxChannel}, numPeriodsPerFrame::Int64, numSamplingPoints::Int64)
  daq.numPeriodsPerFrame = numPeriodsPerFrame
  daq.rxNumSamplingPoints = numSamplingPoints

  for channel in channels
    scannerChannel = daq.params.channels[channel.id]
    channelMapping = scannerChannel.channel # Switch to getter?
    push!(daq.rxChanIdx, channelMapping)
  end
end

function startTx(daq::SimpleSimulatedDAQ)
  daq.txRunning = true
end

function stopTx(daq::SimpleSimulatedDAQ)
  daq.txRunning = false
end

function setTxParams(daq::SimpleSimulatedDAQ, Γ; postpone=false)
end

function currentFrame(daq::SimpleSimulatedDAQ)
  return daq.currentFrame
end

function currentPeriod(daq::SimpleSimulatedDAQ)
  return daq.currentPeriod
end

function disconnect(daq::SimpleSimulatedDAQ)
end

enableSlowDAC(daq::SimpleSimulatedDAQ, enable::Bool, numFrames=0,
              ffRampUpTime=0.4, ffRampUpFraction=0.8) = 1

function readData(daq::SimpleSimulatedDAQ, startFrame, numFrames)
  startPeriod = startFrame*daq.numPeriodsPerFrame
  numPeriods = numFrames*daq.numPeriodsPerFrame

  uMeasPeriods, uRefPeriods = readDataPeriods(daq, startPeriod, numPeriods)

  measShape = (size(uRefPeriods, 1), size(uRefPeriods, 2), daq.numPeriodsPerFrame, numFrames)
  uMeas = reshape(uMeasPeriods, measShape)
  refShape = (size(uRefPeriods, 1), size(uRefPeriods, 2), daq.numPeriodsPerFrame, numFrames)
  uRef = reshape(uRefPeriods, refShape)

  return uMeas, uRef
end

function readDataPeriods(daq::SimpleSimulatedDAQ, startPeriod, numPeriods)
  uMeas = zeros(daq.rxNumSamplingPoints, length(daq.rxChanIdx), numPeriods)u"V"
  uRef = zeros(daq.rxNumSamplingPoints, length(daq.refChanIdx), numPeriods)u"V"

  numSendChannels = size(daq.divider, 2)
  if numSendChannels != length(daq.rxChanIdx) || numSendChannels != length(daq.refChanIdx)
    error("For the simple simulated DAQ we assume a matching number of send, feedback and receive channels.")
  end

  cycle = lcm(daq.divider)/daq.baseFrequency
  for sendChannelIdx in 1:numSendChannels
    scannerChannel = [channel for (id, channel) in daq.params.channels if channel isa TxChannelParams && channel.channelIdx == sendChannelIdx][1]
    t = collect(range(0u"s", stop=cycle-1/daq.baseFrequency, length=daq.rxNumSamplingPoints))

    # Work with field for now
    if dimension(daq.amplitude[1]) == dimension(u"T")
      factor = 1.0u"T/T"
    else
      factor = 1/scannerChannel.calibration
    end

    uₜₓ = zeros(daq.rxNumSamplingPoints)u"V"
    uᵣₓ = zeros(daq.rxNumSamplingPoints)u"V"
    for componentIdx in 1:size(daq.amplitude, 1)
      f = daq.baseFrequency/daq.divider[componentIdx, sendChannelIdx]
      Bₘₐₓ = daq.amplitude[componentIdx, sendChannelIdx, 1]*factor
      ϕ = daq.phase[componentIdx, sendChannelIdx, 1]
      B = Bₘₐₓ.*sin.(2π*f*t.+ϕ)

      uₜₓ += B*scannerChannel.calibration
      uᵣₓ += simulateLangevinInduced(t, B, f, ϕ)
    end
    uᵣₓ = uᵣₓ./maximum(uᵣₓ)*u"V" # We assume a nice LNA ;)

    uMeas[:, sendChannelIdx, :] = repeat(uᵣₓ, outer=(1, numPeriods))
    uRef[:, sendChannelIdx, :] = repeat(uₜₓ, outer=(1, numPeriods))
  end

  totalPeriods = daq.currentPeriod+numPeriods
  daq.currentPeriod = totalPeriods % daq.numPeriodsPerFrame
  daq.currentFrame = totalPeriods ÷ daq.numPeriodsPerFrame

  return uMeas, uRef
end
refToField(daq::SimpleSimulatedDAQ, d::Int64) = 0.0

"Very, very basic simulation of an MPI signal using the Langevin function."
function simulateLangevinInduced(t::Vector{typeof(1.0u"s")}, B::Vector{typeof(1.0u"T")}, f::typeof(1.0u"Hz"), ϕ::typeof(1.0u"rad"))
  Bₘₐₓ = maximum(B)

  c = 0.5e-6 # mol/m^3
  ν = 22.459e3 # mol/m^3
  Mₛ = 477e3 # A/m (for magnetite)
  Dₖ = 30/1e9 # m
  μ₀ = 4π*1e-7 # Vs/Am

  k_B = 1.38064852*1e-23 # J/K (Boltzmann constant)
  Tₐ = 273.15+20 # K

  ξ = (π*Dₖ^3*Mₛ*ustrip.(u"T", B))/(3*k_B*Tₐ)
  ξ̇ = (2π^2*Dₖ^3*Mₛ*ustrip.(u"Hz", f)*ustrip.(u"T", Bₘₐₓ))/(3*k_B*Tₐ)*cos.(2π*ustrip.(u"Hz", f)*ustrip.(u"s", t).+ustrip.(u"rad", ϕ))
  Ṁ = c/(3*ν)*Mₛ*(-ξ̇.*csch.(ξ).^2 + ξ̇./(ξ.^2))

  u = -Ṁ;

  scalingFactor = 1/maximum(x->isnan(x) ? -Inf : x, u)
  u = u.*scalingFactor # Scale to ±1 for the following correction

  # This at least makes the function work for most values of ϕ.
  # I don't think we have to care about all special cases here.
  if ϕ == 0.0
    indices = findall(x->isnan(x), u)
    for index in indices
      if index < length(u)
        u[index] = sign(u[index+1])
      else
        u[index] = sign(u[index-1])
      end
    end

    # Detect jumps, and yes this is crude...
    for i in 1:length(u)-1
      du = u[i]-u[i+1]
      if du > 0.2
        u[i+1] = sign(u[i+2])
      end
    end
  end

  # Scale back
  return u./scalingFactor*u"V"
end