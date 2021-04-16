export SimpleSimulatedDAQ, SimpleSimulatedDAQParams

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
