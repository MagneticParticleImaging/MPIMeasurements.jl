export DAQRedPitayaScpiNew, disconnect, setSlowDAC, getSlowADC, connect,
       setTxParamsAll, disconnect

mutable struct DAQRedPitayaScpiNew <: AbstractDAQ
  params::DAQParams
  rpc::RedPitayaCluster
  acqSeq::Union{AbstractSequence, Nothing}
  samplesPerStep::Int32
end

function DAQRedPitayaScpiNew(params)
  p = DAQParams(params)
  rpc = RedPitayaCluster(params["ip"])
  daq = DAQRedPitayaScpiNew(p, rpc, nothing, 0)
  setACQParams(daq)
  masterTrigger(daq.rpc, false)
  triggerMode(daq.rpc, params["triggerMode"])
  ramWriterMode(daq.rpc, "TRIGGERED")
  modeDAC(daq.rpc, "STANDARD")

  daq.params.currTx = convert(Matrix{ComplexF64}, diagm(daq.params.txLimitVolt ./ 10))
  return daq
end

function updateParams!(daq::DAQRedPitayaScpiNew, params_::Dict)
  connect(daq.rpc)
  
  daq.params = DAQParams(params_)
  
  setACQParams(daq)
end

currentFrame(daq::DAQRedPitayaScpiNew) = currentFrame(daq.rpc)
currentPeriod(daq::DAQRedPitayaScpiNew) = currentPeriod(daq.rpc)


function calibIntToVoltRx(daq::DAQRedPitayaScpiNew)
  return daq.params.calibIntToVolt[:,daq.params.rxChanIdx]
end

function calibIntToVoltRef(daq::DAQRedPitayaScpiNew)
  return daq.params.calibIntToVolt[:,daq.params.refChanIdx]
end

function setACQParams(daq::DAQRedPitayaScpiNew)
  decimation(daq.rpc, daq.params.decimation)

  for l=1:(2*length(daq.rpc))
    offsetDAC(daq.rpc, l, daq.params.txOffsetVolt[l])
    #@show offsetDAC(daq.rpc, l)
  end

  for d=1:numTxChannels(daq)
    for e=1:numTxChannels(daq)
      frequencyDAC(daq.rpc, daq.params.dfChanIdx[d], e, daq.params.dfFreq[e]) 
    end   
    signalTypeDAC(daq.rpc, daq.params.dfChanIdx[d], daq.params.dfWaveform)
    jumpSharpnessDAC(daq.rpc, daq.params.dfChanIdx[d], daq.params.jumpSharpness)
  end
  passPDMToFastDAC(daq.rpc, daq.params.passPDMToFastDAC)

  samplesPerPeriod(daq.rpc, daq.params.rxNumSamplingPoints * daq.params.acqNumAverages)

  periodsPerFrame(daq.rpc, daq.params.acqNumPeriodsPerFrame)
  # Previously slowDACStepsPerFrame
  stepsPerRepetition = div(daq.params.acqNumPeriodsPerFrame,daq.params.acqNumPeriodsPerPatch)
  samplesPerSlowDACStep(daq.rpc, div(samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc), stepsPerRepetition))
  daq.samplesPerStep = samplesPerSlowDACStep(daq.rpc)
  clearSequence(daq.rpc)

  if !isempty(daq.params.acqFFValues) 
    numSlowDACChan(master(daq.rpc), daq.params.acqNumFFChannels)
    lut = daq.params.acqFFValues.*daq.params.calibFFCurrentToVolt
    enable = nothing
    if !isempty(daq.params.acqEnableSequence)
      enable = daq.params.acqEnableSequence
    end
    #TODO IMPLEMENT RAMP DOWN TIMING
    #TODO Distribute sequence on multiple redpitayas, not all the same
    daq.acqSeq = ArbitrarySequence(lut, enable, stepsPerRepetition,
    daq.params.acqNumFrames*daq.params.acqNumFrameAverages, computeRamping(daq.rpc, daq.params.ffRampUpTime, daq.params.ffRampUpFraction))
    appendSequence(daq.rpc, daq.acqSeq)
    # No enable should be equivalent to just full ones, alternatively implement constant function for enableLUT too
    #else # We might want to solve this differently
    #  enableDACLUT(master(daq.rpc), ones(Bool, length(daq.params.acqFFValues)))
    #end
  else
    numSlowDACChan(master(daq.rpc), 0)
    daq.acqSeq = nothing
  end


  numSlowADCChan(daq.rpc, 4)

  return nothing
end

function startTx(daq::DAQRedPitayaScpiNew)
  startADC(daq.rpc)
  masterTrigger(daq.rpc, true)
  @info "Started tx"
end


function prepareTx(daq::DAQRedPitayaScpiNew; allowControlLoop = true)
  stopTx(daq)

  if daq.params.controlPhase && allowControlLoop
    controlLoop(daq)
  else 
    tx = daq.params.calibFieldToVolt.*daq.params.dfStrength.*exp.(im*daq.params.dfPhase)
    setTxParams(daq, convert(Matrix{ComplexF64}, diagm(tx)))
  end
end

function stopTx(daq::DAQRedPitayaScpiNew)
  #setTxParams(daq, zeros(ComplexF64, numTxChannels(daq),numTxChannels(daq)))
  masterTrigger(daq.rpc, false)
  stopADC(daq.rpc)
  #RedPitayaDAQServer.disconnect(daq.rpc)
  @info "Stopped tx"
end

function disconnect(daq::DAQRedPitayaScpiNew)
  RedPitayaDAQServer.disconnect(daq.rpc)
end

function setSlowDAC(daq::DAQRedPitayaScpiNew, value, channel)

  setSlowDAC(daq.rpc, channel, value.*daq.params.calibFFCurrentToVolt[channel])

end

function getSlowADC(daq::DAQRedPitayaScpiNew, channel)
  return getSlowADC(daq.rpc, channel)
end

function getFrameTiming(daq::DAQRedPitayaScpiNew)
  startSample = start(daq.acqSeq) * daq.samplesPerStep
  startFrame = div(startSample, samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
  endFrame = div((length(daq.acqSeq) * daq.samplesPerStep), samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc))
  return startFrame, endFrame
end

function prepareSequence(daq::DAQRedPitayaScpiNew)
  startFrame = 0
  endFrame = 0
  if !isnothing(daq.acqSeq)
    RedPitayaDAQServer.prepareSequence(daq.rpc)
    startFrame, endFrame = getFrameTiming(daq)
  end
  return startFrame, endFrame
end

function enableSequence(daq::DAQRedPitayaScpiNew; prepareSeq = true)
  startFrame = 0
  endFrame = 0
  if prepareSeq 
    startFrame, endFrame = prepareSequence(daq)
  else 
    startFrame, endFrame = getFrameTiming(daq)
  end
  startTx(daq)
  return startFrame, endFrame
end

function setTxParams(daq::DAQRedPitayaScpiNew, Γ)
  if any( abs.(daq.params.currTx) .>= daq.params.txLimitVolt )
    error("This should never happen!!! \n Tx voltage is above the limit")
  end

  for d=1:numTxChannels(daq)
    for e=1:numTxChannels(daq)
      amp = abs(Γ[d,e])
      ph = angle(Γ[d,e])
      phaseDAC(daq.rpc, daq.params.dfChanIdx[d], e, ph )
      amplitudeDAC(daq.rpc, daq.params.dfChanIdx[d], e, amp)
    end
  end
  return nothing
end

#TODO: calibRefToField should be multidimensional
refToField(daq::DAQRedPitayaScpiNew, d::Int64) = daq.params.calibRefToField[d]

mutable struct RedPitayaAsyncBuffer <: AsyncBuffer
  samples::Union{Matrix{Int16}, Nothing}
  performance::Vector{Vector{PerformanceData}}
end
AsyncBuffer(daq::DAQRedPitayaScpiNew) = RedPitayaAsyncBuffer(nothing, Vector{Vector{PerformanceData}}(undef, 1))

channelType(daq::DAQRedPitayaScpiNew) = SampleChunk

function updateAsyncBuffer!(buffer::RedPitayaAsyncBuffer, chunk)
  samples = chunk.samples
  perfs = chunk.performance
  push!(buffer.performance, perfs)
  if !isnothing(buffer.samples)
    buffer.samples = hcat(buffer.samples, samples)
  else 
    buffer.samples = samples
  end
  for (i, p) in enumerate(perfs)
    if p.status.overwritten || p.status.corrupted
        @warn "RedPitaya $i lost data"
    end
end
end

function frameAverageBufferSize(daq::DAQRedPitayaScpiNew, frameAverages) 
  return samplesPerPeriod(daq.rpc), numRxChannels(daq), periodsPerFrame(daq.rpc), frameAverages
end

function endSequence(daq::DAQRedPitayaScpiNew, endFrame)
  currFr =  currentFrame(daq)
  # Wait for sequence to finish
  while currFr < endFrame  
    currFr = currentFrame(daq)
  end
  stopTx(daq)
end
function endSequence(daq::DAQRedPitayaScpiNew)
  startFrame, endFrame = getFrameTiming(daq)
  endSequence(daq, endFrame)
end

function asyncProducer(channel::Channel, daq::DAQRedPitayaScpiNew, numFrames; prepTx = true, prepSeq = true, endSeq = true)
  if prepTx
    prepareTx(daq)
  end
  startFrame, endFrame = enableSequence(daq, prepareSeq = prepSeq)
  
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  startSample = startFrame * samplesPerFrame
  samplesToRead = samplesPerFrame * numFrames
  chunkSize = Int(ceil(0.1 * (125e6/daq.params.decimation)))

  # Start pipeline
  @info "Pipeline started"
  try 
    readPipelinedSamples(daq.rpc, startSample, samplesToRead, channel, chunkSize = chunkSize) 
  catch e
    @error e 
  end
  @info "Pipeline finished"

  if endSeq
    endSequence(daq, endFrame)
  end
end

function convertSamplesToFrames!(buffer::RedPitayaAsyncBuffer, daq::DAQRedPitayaScpiNew)
  unusedSamples = buffer.samples
  samples = buffer.samples
  frames = nothing
  samplesPerFrame = samplesPerPeriod(daq.rpc) * periodsPerFrame(daq.rpc)
  samplesInBuffer = size(samples)[2]
  framesInBuffer = div(samplesInBuffer, samplesPerFrame)
  
  if framesInBuffer > 0
      samplesToConvert = view(samples, :, 1:(samplesPerFrame * framesInBuffer))
      frames = convertSamplesToFrames(samplesToConvert, numChan(daq.rpc), samplesPerPeriod(daq.rpc), periodsPerFrame(daq.rpc), framesInBuffer, daq.params.acqNumAverages, 1)
      

      c = daq.params.calibIntToVolt #is calibIntToVolt ever sanity checked?
      for d = 1:size(frames, 2)
        frames[:, d, :, :] .*= c[1,d]
        frames[:, d, :, :] .+= c[2,d]
      end
      
      if (samplesPerFrame * framesInBuffer) + 1 <= samplesInBuffer
          #samplesBefore = size(samples, 2)
          #removedSamples = samplesPerFrame * framesInBuffer
          #@info "Sample buffer had $samplesBefore samples, removed $removedSamples"
          unusedSamples = samples[:, (samplesPerFrame * framesInBuffer) + 1:samplesInBuffer]
          #samplesLeft = size(unusedSamples, 2)
          #@info "Samples left $samplesLeft"
      else 
        unusedSamples = nothing
      end
  end

  buffer.samples = unusedSamples
  return frames

end

function retrieveMeasAndRef!(buffer::RedPitayaAsyncBuffer, daq::DAQRedPitayaScpiNew)
  frames = convertSamplesToFrames!(buffer, daq)
  uMeas = nothing
  uRef = nothing
  if !isnothing(frames)
    uMeas = frames[:,daq.params.rxChanIdx,:,:]
    uRef = frames[:,daq.params.refChanIdx,:,:]
  end
  return uMeas, uRef
end

function readData(daq::DAQRedPitayaScpiNew, numFrames, startFrame)
  u = readData(daq.rpc, startFrame, numFrames, daq.params.acqNumAverages, 1)

  @info "size u in readData: $(size(u))"
  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

  uMeas = u[:,daq.params.rxChanIdx,:,:]
  uRef = u[:,daq.params.refChanIdx,:,:]

  lostSteps = numLostStepsSlowADC(master(daq.rpc))
  if lostSteps > 0
    @error("WE LOST $lostSteps SLOW DAC STEPS!")
  end  

  return uMeas, uRef
end

function readDataPeriods(daq::DAQRedPitayaScpiNew, numPeriods, startPeriod)
  u = readDataPeriods(daq.rpc, startPeriod, numPeriods, daq.params.acqNumAverages)

  c = daq.params.calibIntToVolt
  for d=1:size(u,2)
    u[:,d,:,:] .*= c[1,d]
    u[:,d,:,:] .+= c[2,d]
  end

  uMeas = u[:,daq.params.rxChanIdx,:]
  uRef = u[:,daq.params.refChanIdx,:]

  return uMeas, uRef
end
