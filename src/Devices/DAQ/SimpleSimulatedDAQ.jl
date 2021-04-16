export DummyDAQ

@option struct SimpleSimulatedDAQParams <: DeviceParams
    samplesPerPeriod::Int
    sendFrequency::typeof(1u"kHz")
end

@quasiabstract struct SimpleSimulatedDAQ <: AbstractDAQ
    handle::Union{String, Nothing}

    function SimpleSimulatedDAQ(deviceID::String, params::SimpleSimulatedDAQParams)
        return new(deviceID, params, nothing)
    end
end

function startTx(daq::DummyDAQ)
end

function stopTx(daq::DummyDAQ)
end

function setTxParams(daq::DummyDAQ, Γ; postpone=false)
end

function currentFrame(daq::DummyDAQ)
    return 1;
end

function currentPeriod(daq::DummyDAQ)
    return 1;
end

function disconnect(daq::DummyDAQ)
end

enableSlowDAC(daq::DummyDAQ, enable::Bool, numFrames=0,
              ffRampUpTime=0.4, ffRampUpFraction=0.8) = 1

function readData(daq::DummyDAQ, startFrame, numFrames)
    uMeas = zeros(daq.params.rxNumSamplingPoints,1,1,1)
    uRef = zeros(daq.params.rxNumSamplingPoints,1,1,1)

    uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
    uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))

    return uMeas, uRef
end

function readDataPeriods(daq::DummyDAQ, startPeriod, numPeriods)
    uMeas = zeros(daq.params.rxNumSamplingPoints,1,1,1)
    uRef = zeros(daq.params.rxNumSamplingPoints,1,1,1)

    uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
    uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
    
    return uMeas, uRef
end
refToField(daq::DummyDAQ, d::Int64) = 0.0
