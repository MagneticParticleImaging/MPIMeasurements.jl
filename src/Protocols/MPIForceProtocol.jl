export MPIForceProtocol, MPIForceProtocolParams
"""
Parameters for the MPIForceProtocol
"""
Base.@kwdef mutable struct MPIForceProtocolParams <: ProtocolParams
  "If set the tx amplitude and phase will be set with control steps"
  controlTx::Bool = false
  "Sequence to measure"
  sequence::Union{Sequence, Nothing} = nothing
end
function MPIForceProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  params = params_from_dict(MPIForceProtocolParams, dict)
  params.sequence = sequence
  return params
end
MPIForceProtocolParams(dict::Dict) = params_from_dict(MPIForceProtocolParams, dict)

Base.@kwdef mutable struct MPIForceProtocol <: Protocol
  @add_protocol_fields MPIForceProtocolParams

  seqMeasState::Union{SequenceMeasState, Nothing} = nothing

  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  txCont::Union{TxDAQController, Nothing} = nothing
  unit::String = ""
end

function requiredDevices(protocol::MPIForceProtocol)
  result = [AbstractDAQ]
  if protocol.params.controlTx
    push!(result, TxDAQController)
  end
  return result
end

function _init(protocol::MPIForceProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  if protocol.params.controlTx
    protocol.txCont = getDevice(protocol.scanner, TxDAQController)
  else
    protocol.txCont = nothing
  end
  return nothing
end

function timeEstimate(protocol::MPIForceProtocol)
  est = "Unknown"
  if !isnothing(protocol.params.sequence)
    params = protocol.params
    seq = params.sequence
    totalFrames = acqNumFrames(seq) * acqNumFrameAverages(seq)
    samplesPerFrame = rxNumSamplingPoints(seq) * acqNumAverages(seq) * acqNumPeriodsPerFrame(seq)
    totalTime = (samplesPerFrame * totalFrames) / (125e6/(txBaseFrequency(seq)/rxSamplingRate(seq)))
    time = totalTime * 1u"s"
    est = string(time)
    @show est
  end
  return est
end

function enterExecute(protocol::MPIForceProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.unit = ""
end

function _execute(protocol::MPIForceProtocol)
  @debug "Measurement protocol started"

  performExperiment(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
end

function performExperiment(protocol::MPIForceProtocol)
  # Start async measurement
  protocol.measuring = true

  sequence = protocol.params.sequence
  daq = getDAQ(protocol.scanner)
  if protocol.params.controlTx
    sequence = controlTx(protocol.txCont, sequence)
  end
  setup(daq, sequence)

  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getRequiredAmplifiers(protocol.scanner, protocol.params.sequence)
  if !isnothing(su)
    enableACPower(su)
  end
  if !isnothing(tempControl)
    disableControl(tempControl)
  end
  @sync for amp in amps
    @async turnOn(amp)
  end
  startTx(daq)
  timing = getTiming(daq)


  # Handle events
  current = 0
  finish = timing.finish
  while current < timing.finish
    current = currentWP(daq.rpc)
    handleEvents(protocol)
    if protocol.cancelled || protocol.stopped
      # TODO move to function of daq
      execute!(daq.rpc) do batch
        for idx in daq.rampingChannel
          @add_batch batch enableRampDown!(daq.rpc, idx, true)
        end
      end
      while !rampDownDone(daq.rpc)
        handleEvents(protocol)
      end
      finish = current
      break
    end
  end

  # TODO Do the following in finally block
  endSequence(daq, finish)
  @sync for amp in amps
    @async turnOff(amp)
  end
  if !isnothing(tempControl)
    enableControl(tempControl)
  end
  if !isnothing(su)
    disableACPower(su)
  end
  protocol.measuring = false

  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEven()))
  end
  if protocol.cancelled
    throw(CancelException())
  end
end


function cleanup(protocol::MPIForceProtocol)
  # NOP
end

function stop(protocol::MPIForceProtocol)
  protocol.stopped = true
end

function resume(protocol::MPIForceProtocol)
   put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end

function cancel(protocol::MPIForceProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::MPIForceProtocol, event::ProgressQueryEvent)
  reply = nothing
  framesTotal = acqNumFrames(protocol.params.sequence)
  framesDone = protocol.measuring ? currentFrame(getDAQ(protocol.scanner)) : 0
  reply = ProgressEvent(framesDone, framesTotal, protocol.unit, event)
  put!(protocol.biChannel, reply)
end

handleEvent(protocol::MPIForceProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

protocolInteractivity(protocol::MPIForceProtocol) = Interactive()
protocolMDFStudyUse(protocol::MPIForceProtocol) = UsingMDFStudy()
