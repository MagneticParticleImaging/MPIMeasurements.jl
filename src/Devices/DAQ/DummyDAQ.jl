export DummyDAQ, DummyDAQParams

Base.@kwdef mutable struct DummyDAQParams <: DeviceParams
  # Here "only" for user/toml parameter
  samplesPerPeriod::Int
  amplitude::Float32 = 1.0
  frequency::Float32 = 1.0
end
DummyDAQParams(dict::Dict) = params_from_dict(DummyDAQParams, dict)

Base.@kwdef mutable struct DummyDAQ <: AbstractDAQ
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyDAQParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  # Here for any other internal parameters
end

function init(daq::DummyDAQ)
  @debug "Initializing dummy DAQ with ID `$(daq.deviceID)`."

  daq.present = true
end

checkDependencies(daq::DummyDAQ) = true

Base.close(daq::DummyDAQ) = nothing

function startTx(daq::DummyDAQ)
end

function stopTx(daq::DummyDAQ)
end

# Version 1
# Parameter list can grow very large, but all are "known" in function signature
#=function setTxParams(daq::DummyDAQ, amplitude, frequency)
  daq.params.amplitude = amplitude # Only set them if they need to be remembered/used obvs
  daq.params.frequency = frequency
  doSomething(daq.params.amplitude)
  doSomething(daq.params.amplitude)
end
function setTxParams(daq::DummyDAQ, sequence::Sequence)
  temp = electricalTxChannels(sequence)
  channels = [channel for channel in temp if channel isa periodicElectricalTxChannels]
  component = components(channels[1])
  setTxParams(daq, amplitude(component), divider(component))
end=#

# Version 2
# Paraemter list is hidden, but if someone wants to call function directly they need to know which parameters to set
function setTxParams(daq::DummyDAQ, sequence::Sequence)
  temp = electricalTxChannels(sequence)
  channels = [channel for channel in temp if channel isa periodicElectricalTxChannels]
  component = components(channels[1])
  daq.params.amplitude = amplitude(component)
  daq.params.frequency = divider(component)
  daq.state = 1
  setTxParams(daq)
end
function setTxParams(daq::DummyDAQ)
  doSomething(daq.params.amplitude)
  doSomething(daq.params.amplitude)
end
# Or maybe an additional helper function, could also be used in f(daq, seq) then
function setTxParams(daq::DummyDAQ, amplitude, frequency)
  daq.params.amplitude = amplitude
  daq.params.frequency = frequency
  setTxParams(daq)
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
    uMeas = zeros(daq.params.samplesPerPeriod,1,1,1)
    uRef = zeros(daq.params.samplesPerPeriod,1,1,1)

    uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.samplesPerPeriod))
    uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.samplesPerPeriod))

    return uMeas, uRef
end

function readDataPeriods(daq::DummyDAQ, startPeriod, numPeriods)
    uMeas = zeros(daq.params.samplesPerPeriod,1,1,1)
    uRef = zeros(daq.params.samplesPerPeriod,1,1,1)

    uMeas[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.samplesPerPeriod))
    uRef[:,1,1,1] = sin.(range(0,2*pi, length=daq.params.samplesPerPeriod))

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
    framesInBuffer = div(samplesInBuffer, daq.params.samplesPerPeriod)

    if framesInBuffer > 0
        samplesToConvert = samples[:, 1:(daq.params.samplesPerPeriod * framesInBuffer)]
        temp = reshape(samplesToConvert, 2, daq.params.samplesPerPeriod, 1, 1)
        frames = zeros(Float32, daq.params.samplesPerPeriod, 2, 1, 1)
        frames[:, 1, :, :] = temp[1, :, :, :]
        frames[:, 2, :, :] = temp[2, :, :, :]

        if (daq.params.samplesPerPeriod * framesInBuffer) + 1 <= samplesInBuffer
            unusedSamples = samples[:, (daq.params.samplesPerPeriod * framesInBuffer) + 1:samplesInBuffer]
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
            samples = zeros(Float32, 2, daq.params.samplesPerPeriod)
            samples[1, :] = daq.params.amplitude * sin.(daq.params.frequency .* range(0,2*pi, length=daq.params.samplesPerPeriod))
            samples[2, :] = daq.params.amplitude * sin.(daq.params.frequency .* range(0,2*pi, length=daq.params.samplesPerPeriod))
            put!(channel, samples)
            currentFrame += 1
        end
    catch e
        @error e
    end
    return endFrame
end

function prepareTx(daq::DummyDAQ, sequence::Sequence; allowControlLoop = true)
    # NOP
end

function setSequenceParams(daq::DummyDAQ, sequence::Sequence)
    # NOP
end

function prepareSequence(daq::DummyDAQ, sequence::Sequence)
    # NOP
end


function endSequence(daq::DummyDAQ, endFrame)
    # NOP
end

function readData(daq::DummyDAQ, startFrame, numFrames, numBlockAverages)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end

function readDataPeriods(daq::DummyDAQ, startPeriod, numPeriods, numBlockAverages)
  uMeas=zeros(2,2,2,2)
  uRef=zeros(2,2,2,2)
  return uMeas, uRef
end

numTxChannelsTotal(daq::DummyDAQ) = 1
numRxChannelsTotal(daq::DummyDAQ) = 1
numTxChannelsActive(daq::DummyDAQ) = 1
numRxChannelsActive(daq::DummyDAQ) = 1
numRxChannelsReference(daq::DummyDAQ) = 0
numRxChannelsMeasurement(daq::DummyDAQ) = 1

canPostpone(daq::DummyDAQ) = false
canConvolute(daq::DummyDAQ) = false
