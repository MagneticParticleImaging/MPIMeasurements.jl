using MPIMeasurements
using ReusePatterns
using Configurations


### This section can be in a different package, which is not coupled to MPIMeasurements.jl as a dependency
@option struct FlexibleDAQParams <: MPIMeasurements.DeviceParams
  samplesPerPeriod::Int
  sendFrequency::typeof(1u"kHz")
end

@quasiabstract struct FlexibleDAQ <: MPIMeasurements.AbstractDAQ
  handle::Union{String, Nothing}

  function FlexibleDAQ(deviceID::String, params::FlexibleDAQParams)
    return new(deviceID, params, nothing)
  end
end

function startTx(daq::FlexibleDAQ)
end

function stopTx(daq::FlexibleDAQ)
end

function setTxParams(daq::FlexibleDAQ, amplitude, phase; postpone=false)
end

function currentFrame(daq::FlexibleDAQ)
    return 1;
end

function currentPeriod(daq::FlexibleDAQ)
    return 1;
end

function readData(daq::FlexibleDAQ, startFrame, numFrames)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end

function readDataPeriods(daq::FlexibleDAQ, startPeriod, numPeriods)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end
refToField(daq::FlexibleDAQ, d::Int64) = 0.0

### / External section

testConfigDir = normpath(string(@__DIR__), "../../test/Scanner/TestConfigs")
addConfigurationPath(testConfigDir)
scanner = MPIScanner("TestFlexibleScanner")