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


function startTx(daq::SimpleSimulatedDAQ)
end

function stopTx(daq::SimpleSimulatedDAQ)
end

function setTxParams(daq::SimpleSimulatedDAQ, amplitude, phase; postpone=false)
end

function currentFrame(daq::SimpleSimulatedDAQ)
    return 1;
end

function currentPeriod(daq::SimpleSimulatedDAQ)
    return 1;
end

function readData(daq::SimpleSimulatedDAQ, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end

function readDataPeriods(daq::SimpleSimulatedDAQ, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end
refToField(daq::SimpleSimulatedDAQ, d::Int64) = 0.0
