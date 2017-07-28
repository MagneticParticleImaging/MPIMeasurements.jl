using Graphics: @mustimplement

import Base: setindex!, getindex

export startTx, stopTx, setTxParams, controlPhaseDone, currentFrame, readData,
      readDataControlled, numRxChannels, numTxChannels, DAQ, dataConversionFactor

@compat abstract type AbstractDAQ end

include("Control.jl")
include("Plotting.jl")

@mustimplement startTx(daq::AbstractDAQ)
@mustimplement stopTx(daq::AbstractDAQ)
@mustimplement setTxParams(daq::AbstractDAQ, amplitude, phase)
@mustimplement currentFrame(daq::AbstractDAQ)
@mustimplement readData(daq::AbstractDAQ, channel, startFrame, numPeriods)
@mustimplement refToField(daq::AbstractDAQ)

numRxChannels(daq::AbstractDAQ) = daq["rxNumChannels"]
numTxChannels(daq::AbstractDAQ) = length(daq["dfDivider"])

include("Parameters.jl")
include("RedPitaya.jl")
include("RedPitayaScpi.jl")
include("Measurements.jl")

function loadParams(daq::AbstractDAQ)
  filename = configFile(daq)
  loadParams(daq, filename)
end

function DAQ(file::String)
  params = loadParams(_configFile(file))
  if params["daq"] == "RedPitaya"
    return DAQRedPitaya(params)
  elseif params["daq"] == "RedPitayaScpi"
    return DAQRedPitayaScpi(params)
  else
    error("$(params["daq"]) not yet implemented!")
  end
end

function _configFile(file::String)
  return Pkg.dir("MPIMeasurements","src","DAQ","Configurations",file)
end

getindex(daq::AbstractDAQ, param::String) = daq.params[param]
function setindex!(daq::AbstractDAQ, value, param::String)
  daq.params[param] = value
end

function init(daq::AbstractDAQ)
  daq["dfFreq"] = daq["dfBaseFrequency"] ./ daq["dfDivider"]
  daq["dfPeriod"] = lcm(daq["dfDivider"]) / daq["dfBaseFrequency"] *
                    daq["acqNumPeriods"]

  if !isinteger(daq["dfDivider"] / daq["decimation"])
    warn("$(daq["dfDivider"]) cannot be divided by $(daq["decimation"])")
  end
  daq["numSampPerPeriod"] = round(Int, lcm(daq["dfDivider"]) / daq["decimation"]  *
                                                                daq["acqNumPeriods"]
                                              )
  daq["rxBandwidth"] = daq["dfBaseFrequency"] / daq["decimation"] / 2
  daq["acqFramePeriod"] = daq["dfPeriod"] * daq["acqNumPatches"]

  D = numTxChannels(daq)
  N = daq["numSampPerPeriod"]
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, daq["dfPeriod"]*daq["dfFreq"][d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
    end
  end
  daq["sinLUT"] = sinLUT
  daq["cosLUT"] = cosLUT
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
