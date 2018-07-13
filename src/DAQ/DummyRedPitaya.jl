

type DummyDAQRedPitaya <: AbstractDAQ
    params::DAQParams
end


function DummyDAQRedPitaya(params)
    p = DAQParams(params)
    return DummyDAQRedPitaya(p)
end


function startTx(daq::DummyDAQRedPitaya)
end

function stopTx(daq::DummyDAQRedPitaya)
end

function setTxParams(daq::DummyDAQRedPitaya, amplitude, phase)
end

function currentFrame(daq::DummyDAQRedPitaya)
    return 1;
end

function readData(daq::DummyDAQRedPitaya, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end

function readDataPeriods(daq::DummyDAQRedPitaya, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end
refToField(daq::DummyDAQRedPitaya, d::Int64) = 0.0
