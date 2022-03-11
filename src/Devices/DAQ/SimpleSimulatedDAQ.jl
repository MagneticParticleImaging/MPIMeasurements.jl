export SimpleSimulatedDAQ, SimpleSimulatedDAQParams, simulateLangevinInduced

Base.@kwdef struct SimpleSimulatedDAQParams <: DAQParams
  "All configured channels of this DAQ device."
  channels::Dict{String, DAQChannelParams}

  temperatureRise::Union{Dict{String, typeof(1.0u"K")}, Nothing} = nothing
  temperatureRiseSlope::Union{Dict{String, typeof(1.0u"s")}, Nothing} = nothing
  phaseChange::Union{Dict{String, typeof(1.0u"rad/K")}, Nothing} = nothing
  amplitudeChange::Union{Dict{String, typeof(1.0u"T/K")}, Nothing} = nothing
end

"Create the params struct from a dict. Typically called during scanner instantiation."
function SimpleSimulatedDAQParams(dict::Dict{String, Any})
  mainSectionFields = ["temperatureRise", "temperatureRiseSlope", "phaseChange", "amplitudeChange"]
  return createDAQParams(SimpleSimulatedDAQParams, dict)
end

Base.@kwdef mutable struct SimpleSimulatedDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimpleSimulatedDAQParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  # The following fields are only used for the simulation state!
  # The desired values for phase and amplitude are left within the sequence controller.
  "Base frequency to derive drive field frequencies."
  baseFrequency::typeof(1.0u"Hz") = 125.0u"MHz"
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
  "Number of samples per period."
  rxNumSamplingPoints::Int64 = 1

  rxChannelIDMapping::Dict{String, Int64} = Dict{String, Int64}()
  rxChanIDs::Vector{String} = []
  refChanIDs::Vector{String} = []

  currentFrame::Int64 = 1
  currentPeriod::Int64 = 1
end

function _init(daq::SimpleSimulatedDAQ)
  # NOP
end

neededDependencies(::SimpleSimulatedDAQ) = [SimulationController]
optionalDependencies(::SimpleSimulatedDAQ) = [TxDAQController, SurveillanceUnit]

Base.close(daq::SimpleSimulatedDAQ) = nothing

function setup(daq::SimpleSimulatedDAQ, sequence::Sequence)
  setupTx(daq, sequence)
  setupRx(daq, sequence)
end

function setupTx(daq::SimpleSimulatedDAQ, sequence::Sequence)
  daq.baseFrequency = txBaseFrequency(sequence)

  channels = electricalTxChannels(sequence)
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

function setupRx(daq::SimpleSimulatedDAQ, sequence::Sequence)
  daq.numPeriodsPerFrame = acqNumPeriodsPerFrame(sequence)
  daq.rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  
  for channel in rxChannels(sequence)
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

function readData(daq::SimpleSimulatedDAQ, startFrame::Integer, numFrames::Integer, numBlockAverages::Integer=1)
  startPeriod = (startFrame-1)*daq.numPeriodsPerFrame+1
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

function readDataPeriods(daq::SimpleSimulatedDAQ, startPeriod::Integer, numPeriods::Integer, numBlockAverages::Integer=1)
  simCont = dependencies(daq, SimulationController)[1]

  uMeas = zeros(daq.rxNumSamplingPoints, length(daq.rxChanIDs), numPeriods)u"V"
  uRef = zeros(daq.rxNumSamplingPoints, length(daq.refChanIDs), numPeriods)u"V"

  numSendChannels = size(daq.divider, 2)
  if numSendChannels != length(daq.rxChanIDs) || numSendChannels != length(daq.refChanIDs)
    error("For the simple simulated DAQ we assume a matching number of send, feedback and receive channels.")
  end

  cycle = lcm(daq.divider)/daq.baseFrequency
  startTime = upreferred(cycle*(startPeriod-1))
  t = collect(range(startTime, stop=startTime+numPeriods*cycle-1/daq.baseFrequency, length=daq.rxNumSamplingPoints*numPeriods))
  
  for (sendChannelID, sendChannel) in [(id, channel) for (id, channel) in daq.params.channels if channel isa DAQTxChannelParams] 
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

    # The temperature rises asymptotically to Tᵢₙᵢₜ+temperatureRise
    Tᵢₙᵢₜ = initialCoilTemperatures(simCont, sendChannelID)
    if t[1] == 0.0u"s"
      ΔT = fill(0.0u"K", size(t))
      ΔT[2:end] = temperatureRise*t[2:end]./(t[2:end].+temperatureRiseSlope)
    else
      ΔT = temperatureRise*t./(t.+temperatureRiseSlope)
    end
    T = Tᵢₙᵢₜ .+ ΔT
    ΔB = ΔT*amplitudeChange
    Δϕ = ΔT*phaseChange

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
      uᵣₓ .+= simulateLangevinInduced(t, Bᵣ, f, ϕ.+Δϕ) # f is not completely correct due to the phase change, but this is only a rough approximation anyways

      # Assumes the same induced voltage from the field as given out with uₜₓ,
      # just with a slight change in phase and amplitude
      uᵣₑ .+= Bᵣ.*sendChannel.calibration
    end
    
    # Assumes one reference and one measurement channel for each send channel
    uMeas[:, sendChannelIdx, :] = reshape(uᵣₓ, (daq.rxNumSamplingPoints, 1, numPeriods))
    uRef[:, sendChannelIdx, :] = reshape(uᵣₑ, (daq.rxNumSamplingPoints, 1, numPeriods))

    # Update temperature in simulation controller for further use in e.g. simulated temperature sensors
    currentCoilTemperatures(simCont, sendChannelID, T[end])
  end

  totalPeriods = daq.currentPeriod+numPeriods
  daq.currentPeriod = totalPeriods % daq.numPeriodsPerFrame
  daq.currentFrame = totalPeriods ÷ daq.numPeriodsPerFrame

  return uMeas, uRef, reshape(t, (daq.rxNumSamplingPoints, numPeriods))
end

numTxChannelsTotal(daq::SimpleSimulatedDAQ) = 10 # Arbitrary number, since we are just simulating
numRxChannelsTotal(daq::SimpleSimulatedDAQ) = 10 # Arbitrary number, since we are just simulating
numTxChannelsActive(daq::SimpleSimulatedDAQ) = length([channel for (id, channel) in daq.params.channels if channel isa TxChannelParams])
numRxChannelsActive(daq::SimpleSimulatedDAQ) = numRxChannelsReference(daq)+numRxChannelsMeasurement(daq)
numRxChannelsReference(daq::SimpleSimulatedDAQ) = length(daq.refChanIDs)
numRxChannelsMeasurement(daq::SimpleSimulatedDAQ) = length(daq.rxChanIDs)
numComponentsMax(daq::SimpleSimulatedDAQ) = 1
canPostpone(daq::SimpleSimulatedDAQ) = false
canConvolute(daq::SimpleSimulatedDAQ) = false

"Very, very basic simulation of an MPI signal using the Langevin function."
function simulateLangevinInduced(t::Vector{typeof(1.0u"s")}, B::Vector{typeof(1.0u"T")}, f::typeof(1.0u"Hz"), ϕ::Union{typeof(1.0u"rad"), Vector{typeof(1.0u"rad")}})
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