export DummyDAQ, DummyDAQParams

@option struct DummyDAQParams <: DeviceParams
    samplesPerPeriod::Int
    sendFrequency::typeof(1u"kHz")
end

@quasiabstract mutable struct DummyDAQ <: AbstractDAQ
    handle::Union{String, Nothing}

    function DummyDAQ(deviceID::String, params::DummyDAQParams)
        return new(deviceID, params, nothing)
    end
end


# function updateParams!(daq::DummyDAQ, params_::Dict)
#   daq.params = DAQParams(params_)
#   #setACQParams(daq)
# end



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
refToField(daq::DummyDAQ, d::Int64) = 0.0