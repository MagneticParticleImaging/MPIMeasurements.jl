export SimpleSimulatedDAQ, SimpleSimulatedDAQParams, simulateLangevinInduced

abstract type ChannelParams end

Base.@kwdef struct Feedback
  channelID::AbstractString
  calibration::Union{typeof(1.0u"V/T"), Nothing} = nothing
end

Base.@kwdef struct TxChannelParams <: ChannelParams
  channel::Int64
  limitPeak::typeof(1.0u"V")
  sinkImpedance::SinkImpedance = SINK_HIGH
  feedback::Union{Feedback, Nothing} = nothing
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
        splattingDict[:channel] = value["channel"]
        splattingDict[:limitPeak] = uparse(value["limitPeak"])
        if haskey(value, "sinkImpedance")
          splattingDict[:sinkImpedance] = value["sinkImpedance"] == "FIFTY_OHM" ? SINK_FIFTY_OHM : SINK_HIGH
        end
        if haskey(value, "feedback")
          channelID=value["feedback"]["channelID"]
          calibration=uparse(value["feedback"]["calibration"])

          splattingDict[:feedback] = Feedback(channelID=channelID, calibration=calibration)
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

Base.@kwdef struct SimpleSimulatedDAQ <: AbstractDAQ
  deviceID::String
  params::SimpleSimulatedDAQParams
end

function startTx(daq::SimpleSimulatedDAQ)
end

function stopTx(daq::SimpleSimulatedDAQ)
end

function setTxParams(daq::SimpleSimulatedDAQ, Γ; postpone=false)
end

function currentFrame(daq::SimpleSimulatedDAQ)
  return 1;
end

function currentPeriod(daq::SimpleSimulatedDAQ)
  return 1;
end

function disconnect(daq::SimpleSimulatedDAQ)
end

enableSlowDAC(daq::SimpleSimulatedDAQ, enable::Bool, numFrames=0,
              ffRampUpTime=0.4, ffRampUpFraction=0.8) = 1

function readData(daq::SimpleSimulatedDAQ, startFrame, numFrames)
  uMeas = zeros(daq.params.rxNumSamplingPoints,1,1,1)
  uRef = zeros(daq.params.rxNumSamplingPoints,1,1,1)

  uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
  uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))

  return uMeas, uRef
end

function readDataPeriods(daq::SimpleSimulatedDAQ, startPeriod, numPeriods)
  uMeas = zeros(daq.params.rxNumSamplingPoints,1,1,1)
  uRef = zeros(daq.params.rxNumSamplingPoints,1,1,1)

  uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
  uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
  
  return uMeas, uRef
end
refToField(daq::SimpleSimulatedDAQ, d::Int64) = 0.0

"Very, very basic simulation of an MPI signal using the Langevin function."
function simulateLangevinInduced(t::Vector{Float64}, f::Float64, Bₘₐₓ::Float64, ϕ::Float64)
  B = Bₘₐₓ*sin.(2π*f*t.+ϕ) # T
  
  c = 0.5e-6 # mol/m^3 (calculated from 0.5 mol/l)
  ν = 22.459e3 # mol/m^3 (calculated from 22.459 kmol/m^3)
  Mₛ = 477e3 # A/m (for magnetite) (calculated from 477 kA/m)
  Dₖ = 30/1e9 # m
  μ₀ = 4π*1e-7 # Vs/Am

  k_B = 1.38064852*1e-23 # J/K (Boltzmann constant)
  Tₐ = 273.15+20 # K

  ξ = (π*Dₖ^3*Mₛ*B)/(3*k_B*Tₐ)
  ξ̇ = (2π^2*Dₖ^3*Mₛ*f*Bₘₐₓ)/(3*k_B*Tₐ)*cos.(2π*f*t.+ϕ)
  Ṁ = c/(3*ν)*Mₛ*(-ξ̇.*csch.(ξ).^2 + ξ̇./(ξ.^2))

  u = -Ṁ;
  u = u./maximum(x->isnan(x) ? -Inf : x, u) # We assume a nice LNA ;)

  # This at least makes the function work for most values of ϕ.
  # I don't think we have to care about all special cases here.
  if ϕ == 0
    indices = findall(x->isnan(x), Ṁ)
    for index in indices
      if index < length(Ṁ)
        Ṁ[index+1] = sign(Ṁ[index+1])
      else
        Ṁ[index+1] = sign(Ṁ[index-1])
      end
    end
  end

  return u
end