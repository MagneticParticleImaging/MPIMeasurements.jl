

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

mutable struct DummyAsyncBuffer <: AsyncBuffer
    samples::Union{Matrix{Float32}, Nothing}
end

function channelType(daq::DummyDAQ)
    return Matrix{Float32}
end

function AsyncBuffer(daq::DummyDAQ)
    return DummyAsyncBuffer(nothing)
end

function frameAverageBufferSize(daq::DummyDAQ, frameAverages) 
    # 1 Rx channel and 1 period per frame
    return daq.params.rxNumSamplingPoints, 1, 1, frameAverages
end

function updateAsyncBuffer!(buffer::DummyAsyncBuffer, chunk)
    samples = chunk
    if !isnothing(buffer.samples)
        buffer.samples = hcat(buffer.samples, samples)
    else
        buffer.samples = samples
    end
end

function retrieveMeasAndRef!(buffer::DummyAsyncBuffer, daq::DummyDAQ)
    unusedSamples = buffer.samples
    samples = unusedSamples
    frames = nothing
    samplesInBuffer = size(samples)[2]
    framesInBuffer = div(samplesInBuffer, daq.params.rxNumSamplingPoints)
    
    if framesInBuffer > 0
        samplesToConvert = samples[:, 1:(daq.params.rxNumSamplingPoints * framesInBuffer)]
        temp = reshape(samplesToConvert, 2, daq.params.rxNumSamplingPoints, 1, 1)
        frames = zeros(Float32, daq.params.rxNumSamplingPoints, 2, 1, 1)
        frames[:, 1, :, :] = temp[1, :, :, :]
        frames[:, 2, :, :] = temp[2, :, :, :]
        
        if (daq.params.rxNumSamplingPoints * framesInBuffer) + 1 <= samplesInBuffer
            unusedSamples = samples[:, (daq.params.rxNumSamplingPoints * framesInBuffer) + 1:samplesInBuffer]
        else 
          unusedSamples = nothing
        end
  
    end

    buffer.samples = unusedSamples
    
    uMeas = nothing
    uRef = nothing
    if !isnothing(frames)
        uMeas = frames[:, [1], :, :]
        uRef = frames[:, [2], :, :]
    end

    return uMeas, uRef
end

function startProducer(channel::Channel, daq::DummyDAQ)
    startTx(daq)    
    startFrame = 1
    endFrame = numFrames + 1
    currentFrame = startFrame
    try 
        while currentFrame < endFrame
            samples = zeros(Float32, 2, daq.params.rxNumSamplingPoints)
            samples[1, :] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
            samples[2, :] = sin.(range(0,2*pi, length=daq.params.rxNumSamplingPoints))
            put!(channel, samples)
            currentFrame += 1
        end
    catch e
        @error e
    end
end

function prepareTx(daq::DummyDAQ; allowControlLoop = true)
    # NOP
end

function setSequenceParams(daq::DummyDAQ)
    # NOP
end

function prepareSequence(daq::DummyDAQ)
    # NOP
end

function endSequence(daq::DummyDAQ, endFrame)
    # NOP
end