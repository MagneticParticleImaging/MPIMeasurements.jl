export DummyDAQ

@option struct SimulatedDAQParams <: DeviceParams
    samplesPerPeriod::Int
    sendFrequency::typeof(1u"kHz")
end

@quasiabstract struct SimulatedDAQ <: AbstractDAQ
    handle::Union{String, Nothing}

    function SimulatedDAQ(deviceID::String, params::DummyDAQParams)
        return new(deviceID, params, nothing)
    end
end


function startTx(daq::SimulatedDAQ)
end

function stopTx(daq::SimulatedDAQ)
end

function setTxParams(daq::SimulatedDAQ, amplitude, phase; postpone=false)
end

function currentFrame(daq::SimulatedDAQ)
    return 1;
end

function currentPeriod(daq::SimulatedDAQ)
    return 1;
end

function readData(daq::SimulatedDAQ, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end

function readDataPeriods(daq::SimulatedDAQ, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end
refToField(daq::SimulatedDAQ, d::Int64) = 0.0
