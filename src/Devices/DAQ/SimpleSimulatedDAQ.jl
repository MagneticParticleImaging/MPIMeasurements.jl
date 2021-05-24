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
  channelIdx::Int64
end

Base.@kwdef struct SimpleSimulatedDAQParams <: DeviceParams
  channels::Dict{String, ChannelParams}

  temperatureRise::Union{Dict{String, typeof(1.0u"K")}, Nothing} = nothing
  temperatureRiseSlope::Union{Dict{String, typeof(1.0u"s")}, Nothing} = nothing
  phaseChange::Union{Dict{String, typeof(1.0u"rad/K")}, Nothing} = nothing
  amplitudeChange::Union{Dict{String, typeof(1.0u"T/K")}, Nothing} = nothing
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function SimpleSimulatedDAQParams(dict::Dict)
  mainSectionFields = ["temperatureRise", "temperatureRiseSlope", "phaseChange", "amplitudeChange"]
  
  channels = Dict{String, ChannelParams}()
  for (key, value) in dict
    if value isa Dict && !(key in mainSectionFields)
      splattingDictInner = Dict{Symbol, Any}()
      if value["type"] == "tx"
        splattingDictInner[:channelIdx] = value["channel"]
        splattingDictInner[:limitPeak] = uparse(value["limitPeak"])

        if haskey(value, "sinkImpedance")
          splattingDictInner[:sinkImpedance] = value["sinkImpedance"] == "FIFTY_OHM" ? SINK_FIFTY_OHM : SINK_HIGH
        end

        if haskey(value, "allowedWaveforms")
          splattingDictInner[:allowedWaveforms] = toWaveform.(value["allowedWaveforms"])
        end

        if haskey(value, "feedback")
          channelID=value["feedback"]["channelID"]
          calibration=uparse(value["feedback"]["calibration"])

          splattingDictInner[:feedback] = Feedback(channelID=channelID, calibration=calibration)
        end

        if haskey(value, "calibration")
          splattingDictInner[:calibration] = uparse.(value["calibration"])
        end

        channels[key] = TxChannelParams(;splattingDictInner...)
      elseif value["type"] == "rx"
        channels[key] = RxChannelParams(channelIdx=value["channel"])
      end

      # Remove key in order to process the rest with the standard function
      delete!(dict, key)
    end
  end

  splattingDict = dict_to_splatting(dict)
  splattingDict[:channels] = channels

  try
    return SimpleSimulatedDAQParams(;splattingDict...)
  catch e
    if e isa UndefKeywordError
      throw(ScannerConfigurationError("The required field `$(e.var)` is missing in your configuration "*
                                      "for a device with the params type `SimpleSimulatedDAQParams`."))
    elseif e isa MethodError
      @warn e.args e.world e.f
      throw(ScannerConfigurationError("A required field is missing in your configuration for a device "*
                                      "with the params type `SimpleSimulatedDAQParams`. Please check "*
                                      "the causing stacktrace."))
    else
      rethrow()
    end
  end
end

Base.@kwdef mutable struct SimpleSimulatedDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimpleSimulatedDAQParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  # The following fields are only used for the simulation state!
  # The desired values for phase and amplitude are left within the sequence controller.
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

  rxChannelIDMapping::Dict{String, Int64} = Dict{String, Int64}()
  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []
  rxNumSamplingPoints::Int64 = 0

  currentFrame::Int64 = 1
  currentPeriod::Int64 = 1
end

function init(daq::SimpleSimulatedDAQ)
  @info "Initializing simple simulated DAQ with ID `$(daq.deviceID)`."
end

function checkDependencies(daq::SimpleSimulatedDAQ)
  dependencies_ = dependencies(daq)
  if length(dependencies_) > 1
    throw(ScannerConfigurationError("The simple simulated DAQ device with ID `$(deviceID(daq))` "*
                                    "has more than one dependency assigned but "*
                                    "it only needs one simulation controller."))
  elseif length(dependencies_) == 0
    throw(ScannerConfigurationError("The simple simulated DAQ device with ID `$(deviceID(daq))` "*
                                    "has no dependencies assigned but "*
                                    "it needs one simulation controller."))
  elseif !(collect(values(dependencies_))[1] isa SimulationController)
    throw(ScannerConfigurationError("The simple simulated DAQ device with ID `$(deviceID(daq))` "*
                                    "has a dependency assigned but it is not a simulation "*
                                    "controller but a `$(typeof(values(dependencies_)[1]))`."))
  else
    return true
  end                            
end

function setupTx(daq::SimpleSimulatedDAQ, channels::Vector{ElectricalTxChannel}, baseFrequency::typeof(1.0u"Hz"))
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
      feedbackChannelID = scannerChannel.feedback.channelID
      scannerFeedbackChannel = daq.params.channels[feedbackChannelID]
      feedbackChannelIdx = scannerFeedbackChannel.channelIdx # Switch to getter?
      push!(daq.refChanIDs, feedbackChannelID)
      daq.rxChannelIDMapping[feedbackChannelID] = feedbackChannelIdx
    end

    componentIndex = 1
    for component in channel.components
      daq.divider[componentIndex, channelMapping, 1] = component.divider
      daq.phase[componentIndex, channelMapping, 1] = component.phase[1] # Only one period is allowed for now
      daq.waveform[componentIndex, channelMapping] = component.waveform # Only one period is allowed for now
      daq.amplitude[componentIndex, channelMapping, 1] = component.amplitude[1] # Only one period is allowed for now
      componentIndex += 1
    end
  end
end

function setupRx(daq::SimpleSimulatedDAQ, channels::Vector{RxChannel}, numPeriodsPerFrame::Int64, numSamplingPoints::Int64)
  daq.numPeriodsPerFrame = numPeriodsPerFrame
  daq.rxNumSamplingPoints = numSamplingPoints

  for channel in channels
    scannerChannel = daq.params.channels[channel.id]
    push!(daq.rxChanIDs, channel.id)
    daq.rxChannelIDMapping[channel.id] = scannerChannel.channelIdx
  end
end

function startTx(daq::SimpleSimulatedDAQ)
  daq.txRunning = true
end

function stopTx(daq::SimpleSimulatedDAQ)
  daq.txRunning = false
end

function setTxParams(daq::SimpleSimulatedDAQ, Γ; postpone=false)
# Needs to update period and frame
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

  uMeasPeriods, uRefPeriods, t = readDataPeriods(daq, startPeriod, numPeriods)

  measShape = (size(uMeasPeriods, 1), size(uMeasPeriods, 2), daq.numPeriodsPerFrame, numFrames)
  uMeas = reshape(uMeasPeriods, measShape)
  refShape = (size(uRefPeriods, 1), size(uRefPeriods, 2), daq.numPeriodsPerFrame, numFrames)
  uRef = reshape(uRefPeriods, refShape)
  tShape = (size(t, 1), daq.numPeriodsPerFrame, numFrames)
  t = reshape(t, tShape)

  return uMeas, uRef, t
end

function readDataPeriods(daq::SimpleSimulatedDAQ, startPeriod, numPeriods)
  simCont = dependencies(daq, SimulationController)[1]

  uMeas = zeros(daq.rxNumSamplingPoints, length(daq.rxChanIDs), numPeriods)u"V"
  uRef = zeros(daq.rxNumSamplingPoints, length(daq.refChanIDs), numPeriods)u"V"

  numSendChannels = size(daq.divider, 2)
  if numSendChannels != length(daq.rxChanIDs) || numSendChannels != length(daq.refChanIDs)
    error("For the simple simulated DAQ we assume a matching number of send, feedback and receive channels.")
  end

  cycle = lcm(daq.divider)/daq.baseFrequency
  startTime = cycle*(startPeriod-1) |> u"s"
  t = collect(range(startTime, stop=startTime+numPeriods*cycle-1/daq.baseFrequency, length=daq.rxNumSamplingPoints*numPeriods))

  for (sendChannelID, sendChannel) in [(id, channel) for (id, channel) in daq.params.channels if channel isa TxChannelParams] 
    sendChannelIdx = sendChannel.channelIdx

    # Work with field for now
    if dimension(daq.amplitude[1]) == dimension(u"T")
      factor = 1.0u"T/T"
    else
      factor = 1/scannerChannel.calibration
    end


    temperatureRise = daq.params.temperatureRise[sendChannelID]
    temperatureRiseSlope = daq.params.temperatureRiseSlope[sendChannelID]
    phaseChange = daq.params.phaseChange[sendChannelID]
    amplitudeChange = daq.params.amplitudeChange[sendChannelID]

    ΔT = temperatureRise*t./(t.+temperatureRiseSlope)
    T = initialCoilTemperatures(simCont)[sendChannelID] .+ ΔT
    ΔB = T*amplitudeChange
    Δϕ = T*phaseChange

    uₜₓ = zeros(length(t))u"V"
    uᵣₓ = zeros(length(t))u"V"
    uᵣₑ = zeros(length(t))u"V"
    for componentIdx in 1:size(daq.amplitude, 1)
      f = daq.baseFrequency/daq.divider[componentIdx, sendChannelIdx]
      Bₘₐₓ = daq.amplitude[componentIdx, sendChannelIdx, 1]*factor
      ϕ = daq.phase[componentIdx, sendChannelIdx, 1]

      Bᵢ = Bₘₐₓ.*sin.(2π*f*t.+ϕ) # Desired, ideal field without drift
      Bᵣ = (Bₘₐₓ.+ΔB).*sin.(2π*f*t.+ϕ.+Δϕ) # Field with drift of phase and amplitude

      uₜₓ .+= Bᵢ.*sendChannel.calibration
      uᵣₓ .+= simulateLangevinInduced(t, Bᵣ, f, ϕ)

      # Assumes the same induced voltage from the field as given out with uₜₓ,
      # just with a slight change in phase and amplitude
      uᵣₑ .+= Bᵣ.*sendChannel.calibration
    end

    # Assumes one reference and one measurement channel for each send channel
    uMeas[:, sendChannelIdx, :] = reshape(uᵣₓ, (daq.rxNumSamplingPoints, 1, numPeriods))
    uRef[:, sendChannelIdx, :] = reshape(uᵣₑ, (daq.rxNumSamplingPoints, 1, numPeriods))
  end

  totalPeriods = daq.currentPeriod+numPeriods
  daq.currentPeriod = totalPeriods % daq.numPeriodsPerFrame
  daq.currentFrame = totalPeriods ÷ daq.numPeriodsPerFrame

  return uMeas, uRef, reshape(t, (daq.rxNumSamplingPoints, numPeriods))
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

  u = -Ṁ; # Yes, this is wrong since it doesn't reflect the coil geometry or anything else, but I don't care at this point

  scalingFactor = 1/maximum(x->isnan(x) ? -Inf : x, u)
  u = u.*scalingFactor # Scale to ±1 for the following correction and leave it like that; we assume a nice LNA ;)

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

  return u*u"V"
end