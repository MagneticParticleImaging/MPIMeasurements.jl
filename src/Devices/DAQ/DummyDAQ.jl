export DummyDAQ, DummyDAQParams

Base.@kwdef struct DummyDAQParams <: DeviceParams
  samplesPerPeriod::Int
  sendFrequency::typeof(1u"kHz")
end
DummyDAQParams(dict::Dict) = params_from_dict(DummyDAQParams, dict)

Base.@kwdef mutable struct DummyDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyDAQParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

function init(daq::DummyDAQ)
  @debug "Initializing dummy DAQ with ID `$(daq.deviceID)`."
end

checkDependencies(daq::DummyDAQ) = true

function startTx(daq::DummyDAQ)
end

function stopTx(daq::DummyDAQ)
end

function setTxParams(daq::DummyDAQ, amplitude, phase; postpone=false)
end

function currentFrame(daq::DummyDAQ)
    return 1;
end

function currentPeriod(daq::DummyDAQ)
    return 1;
end

function readData(daq::DummyDAQ, startFrame, numFrames)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end

function readDataPeriods(daq::DummyDAQ, startPeriod, numPeriods)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end

numTxChannels(daq::DummyDAQ) = 1
numRxChannels(daq::DummyDAQ) = 1
canPostpone(daq::DummyDAQ) = false
canConvolute(daq::DummyDAQ) = false
