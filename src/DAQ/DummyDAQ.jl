

mutable struct DummyDAQ <: AbstractDAQ
    params::DAQParams

    function DummyDAQ(params)
        p = DAQParams(params)
        return new(p)
    end
end


function updateParams!(daq::DummyDAQ, params_::Dict)
  daq.params = DAQParams(params_)
  #setACQParams(daq)
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

enableSequence(daq::DummyDAQ, enable::Bool, numFrames=0,
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
