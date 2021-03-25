using MPIMeasurements


### This section can be in a different package, which is not coupled to MPIMeasurements.jl as a dependency
mutable struct FlexibleDummyDAQ <: AbstractDAQ
    params::DAQParams

    function FlexibleDummyDAQ(params)
        p = DAQParams(params)
        return new(p)
    end
end


function updateParams!(daq::FlexibleDummyDAQ, params_::Dict)
  daq.params = DAQParams(params_)
  #setACQParams(daq)
end



function startTx(daq::FlexibleDummyDAQ)
end

function stopTx(daq::FlexibleDummyDAQ)
end

function setTxParams(daq::FlexibleDummyDAQ, amplitude, phase; postpone=false)
end

function currentFrame(daq::FlexibleDummyDAQ)
    return 1;
end

function currentPeriod(daq::FlexibleDummyDAQ)
    return 1;
end

function readData(daq::FlexibleDummyDAQ, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end

function readDataPeriods(daq::FlexibleDummyDAQ, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
end
refToField(daq::FlexibleDummyDAQ, d::Int64) = 0.0

### / External section


scanner = MPIScanner("FlexibleDummyScanner.toml")
daq = getDAQ(scanner)

@info "The type of DAQ is $(typeof(daq)), which awesome, because we did not define it within MPIMeasurements.jl"

params = toDict(daq.params)

params["studyName"]="TestDummy"
params["studyDescription"]="A very cool measurement"
params["scannerOperator"]="Dummy"
params["dfStrength"]=[1e-3]
params["acqNumFrames"]=100
params["acqNumAverages"]=10

# Can't have a measurement under Windows yet due to not including Measurements.jl in main file
#filename = measurement(daq, params, MDFStore, controlPhase=true)
