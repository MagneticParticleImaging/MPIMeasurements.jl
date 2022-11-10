export RobotBasedMagneticFieldStaticProtocolParams, RobotBasedMagneticFieldStaticProtocol, measurement, filename

Base.@kwdef mutable struct RobotBasedMagneticFieldStaticProtocolParams <: RobotBasedProtocolParams
  sequence::Union{Sequence, Nothing} = nothing
  positions::Union{GridPositions, Nothing} = nothing
  description::String = ""
  #postMoveWaitTime::typeof(1.0u"s") = 0.5u"s"
  #numCooldowns::Integer = 0
  #robotVelocity::typeof(1.0u"m/s") = 0.01u"m/s"
  #switchBrakes::Bool = false
end
function RobotBasedMagneticFieldStaticProtocolParams(dict::Dict, scanner::MPIScanner)
  if haskey(dict, "Positions")
    posDict = dict["Positions"]

    positions = Positions(posDict)
    delete!(dict, "Positions")
  else 
    positions = nothing
  end

  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  
  params = params_from_dict(RobotBasedMagneticFieldStaticProtocolParams, dict)
  params.positions = positions
  params.sequence = sequence
  return params
end

Base.@kwdef mutable struct RobotBasedMagneticFieldStaticProtocol <: RobotBasedProtocol
  @add_protocol_fields RobotBasedMagneticFieldStaticProtocolParams

  stopped::Bool = false
  cancelled::Bool = false
  restored::Bool = false
  finishAcknowledged::Bool = false

  measurement::Union{MagneticFieldMeasurement, Nothing} = nothing
  currPos::Int64 = 1
  #safetyTask::Union{Task, Nothing} = nothing
  #safetyChannel::Union{Channel{ProtocolEvent}, Nothing} = nothing
end

function _init(protocol::RobotBasedMagneticFieldStaticProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  measurement_ = MagneticFieldMeasurement()
  MPIFiles.description(measurement_, protocol.params.description)
  MPIFiles.positions(measurement_, protocol.params.positions)
  # TODO Check positions
  protocol.measurement = measurement_
end

function enterExecute(protocol::RobotBasedMagneticFieldStaticProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.currPos = 1
end

function nextPosition(protocol::RobotBasedMagneticFieldStaticProtocol)
  positions = protocol.params.positions
  if protocol.currPos <= length(positions)
    return ScannerCoords(uconvert.(Unitful.mm, positions[protocol.currPos]))
  end
  return nothing
end

function preMovement(protocol::RobotBasedMagneticFieldStaticProtocol)
  @info "Curr Pos in Magnetic Field Protocol $(protocol.currPos)"
end

function duringMovement(protocol::RobotBasedMagneticFieldStaticProtocol, moving::Task)
  daq = getDAQ(protocol.scanner)
  # Prepare Sequence
  setup(daq, protocol.params.sequence) #TODO setupTx might be fine once while setupRx needs to be done for each new sequence
  prepareTx(daq, protocol.params.sequence)
  setSequenceParams(daq, protocol.params.sequence) # TODO make this nicer and not redundant
end

function postMovement(protocol::RobotBasedMagneticFieldStaticProtocol)
  # Prepare
  index = protocol.currPos
  @info "Measurement" index length(protocol.params.positions)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(vcat(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
  enableACPower(su)
  disableControl(tempControl)
  @sync for amp in amps
    @async turnOn(amp)
  end

  # Start measurement
  producer = @tspawnat protocol.scanner.generalParams.producerThreadID performMeasurement(protocol)
  while !istaskdone(producer)
    handleEvents(protocol)
    # Dont want to throw cancel here
    sleep(0.05)
  end

  # Increment measured positions
  protocol.currPos +=1
  
  # End measurement
  timing = getTiming(daq) 
  endSequence(daq, timing.finish)
  @sync for amp in amps
    @async turnOff(amp)
  end
  enableControl(tempControl)
  disableACPower(su)
end

function performMeasurement(protocol::RobotBasedMagneticFieldStaticProtocol)
  daq = getDAQ(protocol.scanner)
  gaussmeter = getGaussMeter(scanner(protocol))
  addMeasuredPosition(measurement(protocol), pos, field=field_, fieldError=fieldError_, fieldFrequency=fieldFrequency_, timestamp=timestamp_, temperature=temperature_)

  timing = getTiming(daq)
  startTx(daq)
  current = 0
  # Wait for measurement proper frame to start
  while current < timing.start
    current = currentWP(daq.rpc)
  end
  
  field_ = getXYZValues(gaussmeter)
  
  if currentWP(daq.rpc) < timing.finish
    @warn "Magnetic field was measured too late"
  end
  
  fieldError_ = calculateFieldError(gaussmeter, field_)
  fieldFrequency_ = getFrequency(gaussmeter)
  timestamp_ = now()
  temperature_ = getTemperature(gaussmeter)
  addMeasuredPosition(measurement(protocol), pos, field=field_, fieldError=fieldError_, fieldFrequency=fieldFrequency_, timestamp=timestamp_, temperature=temperature_)
end

function stop(protocol::RobotBasedMagneticFieldStaticProtocol)
  if protocol.currPos <= length(protocol.params.positions)
    # OperationSuccessfulEvent is put when it actually is in the stop loop
    protocol.stopped = true
  else 
    # Stopped has no concept once all measurements are done
    put!(protocol.biChannel, OperationUnsuccessfulEvent(StopEvent()))
  end
end

function resume(protocol::RobotBasedMagneticFieldStaticProtocol)
  protocol.stopped = false
  protocol.restored = true
  # OperationSuccessfulEvent is put when it actually leaves the stop loop
end

function cancel(protocol::RobotBasedMagneticFieldStaticProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end


function handleEvent(protocol::RobotBasedMagneticFieldStaticProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel, ProgressEvent(protocol.currPos, length(protocol.params.positions), "Position", event))
end

handleEvent(protocol::RobotBasedMagneticFieldStaticProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::RobotBasedMagneticFieldStaticProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  saveMagneticFieldAsHDF5(protocol.measurement, filename)
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

protocolInteractivity(protocol::RobotBasedMagneticFieldStaticProtocol) = Interactive()
