using Graphics: @mustimplement

import Base: setindex!, getindex

export AbstractDAQ, startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels, DAQ, dataConversionFactor,
      readDataPeriod, currentPeriod, getDAQ, getDAQs

abstract type AbstractDAQ <: Device end

@enum SinkImpedance begin
  SINK_FIFTY_OHM
  SINK_HIGH
end

Base.@kwdef mutable struct SendParameters
  "Base frequency to derive drive field frequencies (Unit: Hz)"
  baseFrequency::Int64
  "Divider of the baseFrequency to determine the drive field frequencies"
  divider::Array{Int64, 2}
  "Applied drive field phase (Unit: rad)."
  phase::Array{Float64, 3}
  "Applied drive field voltage (Unit: V)."
  amplitude::Array{Float64, 3}
  "Waveform type: sine, triangle or custom"
  waveform::Array{Waveform, 2}
  "Impedance of the sink. Used to calculate the actual output amplitude."
  sinkImpedance::Vector{SinkImpedance}
  "Channels that should be enabled."
  channelMapping::Vector{Int64}
  "Minimum cycles that are performed for an amplitude and phase change."
  minimumChangeCyles::Int64
  "Amplification of the channels (Unit: V)."
  amplification::Vector{Float64}
end

#include("Control.jl")
#include("Plotting.jl")
#include("Parameters.jl")

@mustimplement setupTx(daq::AbstractDAQ, channels::Vector{ElectricalTxChannel})
@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement correctAmpAndPhase(daq::AbstractDAQ, correctionAmp, correctionPhase; convoluted=true)
@mustimplement trigger(daq::AbstractDAQ)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, startFrame, numFrames)
@mustimplement readDataPeriods(daq::AbstractDAQ, startPeriod, numPeriods)
@mustimplement numTxChannels(daq::AbstractDAQ)
@mustimplement numRxChannels(daq::AbstractDAQ)

getDAQs(scanner::MPIScanner) = getDevices(scanner, AbstractDAQ)
function getDAQ(scanner::MPIScanner)
  daqs = getDAQs(scanner)
  if length(daqs) > 1
    error("The scanner has more than one DAQ device. Therefore, a single DAQ cannot be retrieved unambiguously.")
  else
    return daqs[1]
  end
end

function startTxAndControl(daq::AbstractDAQ)
  startTx(daq)
  controlLoop(daq)
end

#include("RedPitayaDAQ.jl")
include("DummyDAQ.jl")
include("SimpleSimulatedDAQ.jl")

function initLUT(N,D, dfCycle, dfFreq)
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, dfCycle*dfFreq[d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
    end
  end
  return sinLUT, cosLUT
end

function dataConversionFactor(daq::AbstractDAQ) #default
  factor = zeros(2,numRxChannels(daq))
  factor[1,:] = 1.0
  factor[2,:] = 0.0
  return factor
end

function readDataControlled(daq::AbstractDAQ, numFrames)
  controlLoop(daq)
  readData(daq, numFrames, currentFrame(daq))
end

#include("TransferFunction.jl")