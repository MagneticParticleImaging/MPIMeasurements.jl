export RobotBasedTDesignFieldProtocolParams, RobotBasedTDesignFieldProtocol, measurement

"""
Parameters for the `RobotBasedTDesignFieldProtocol`

$FIELDS
"""
Base.@kwdef mutable struct RobotBasedTDesignFieldProtocolParams <: RobotBasedProtocolParams
  sequence::Union{Sequence, Nothing} = nothing
  radius::typeof(1.0u"mm") = 0.0u"mm"
  center::ScannerCoords = ScannerCoords([0.0u"mm", 0.0u"mm", 0.0u"mm"])
  N::Int64
  T::Int64
end
function RobotBasedTDesignFieldProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end
  
  params = params_from_dict(RobotBasedTDesignFieldProtocolParams, dict)
  params.sequence = sequence
  return params
end

Base.@kwdef mutable struct RobotBasedTDesignFieldProtocol <: RobotBasedProtocol
  @add_protocol_fields RobotBasedTDesignFieldProtocolParams

  stopped::Bool = false
  cancelled::Bool = false
  restored::Bool = false
  finishAcknowledged::Bool = false

  measurement::Union{Matrix{Float64}, Nothing} = nothing
  tDesign::Union{SphericalTDesign, Nothing} = nothing
  positions::Union{Vector{ScannerCoords}, Nothing} = nothing
  indices::Union{Vector{Int64}, Nothing} = nothing
  currPos::Int64 = 1
  finalizer::Union{Task, Nothing} = nothing
  #safetyTask::Union{Task, Nothing} = nothing
  #safetyChannel::Union{Channel{ProtocolEvent}, Nothing} = nothing
end

function _init(protocol::RobotBasedTDesignFieldProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  protocol.tDesign = loadTDesign(protocol.params.T, protocol.params.N, protocol.params.radius, protocol.params.center.data)
  (pos, indices) = sortPositions(protocol, protocol.tDesign)
  protocol.positions = pos
  protocol.indices = indices
  protocol.measurement = zeros(Float64, 3, length(protocol.tDesign))
end

function sortPositions(protocol::RobotBasedTDesignFieldProtocol, tDesign::SphericalTDesign)
  robot = getRobot(protocol.scanner)
  current = getPositionScannerCoords(robot)
  return sortPositions(tDesign, current)
end

function sortPositions(tDesign::SphericalTDesign, start)
  current = start
  tempPositions = collect(tDesign)
  greedyPositions = ScannerCoords[]
  indices = Int64[]
  while length(greedyPositions) != length(tDesign)
    (val, idx) = findmin(map(x-> norm(x - current), tempPositions))
    current = tempPositions[idx]
    push!(greedyPositions, ScannerCoords(uconvert.(Unitful.mm, current)))
    push!(indices, idx)
    tempPositions[idx] = [Inf, Inf, Inf] .* 1.0u"mm"
  end
  return (greedyPositions, indices)
end

function enterExecute(protocol::RobotBasedTDesignFieldProtocol)
  protocol.stopped = false
  protocol.cancelled = false
  protocol.finishAcknowledged = false
  protocol.restored = false
  protocol.currPos = 1
end

function nextPosition(protocol::RobotBasedTDesignFieldProtocol)
  positions = protocol.positions
  if protocol.currPos <= length(positions)
    return protocol.positions[protocol.currPos]
  end
  return nothing
end

function preMovement(protocol::RobotBasedTDesignFieldProtocol)
  @info "Curr Pos in Magnetic Field Protocol $(protocol.currPos)"
end

function duringMovement(protocol::RobotBasedTDesignFieldProtocol, moving::Task)
  wait(protocol.finalizer)
  daq = getDAQ(protocol.scanner)
  # Prepare Sequence
  setup(daq, protocol.params.sequence)
end

function postMovement(protocol::RobotBasedTDesignFieldProtocol)
  # Prepare
  index = protocol.currPos
  @info "Measurement" index length(protocol.positions)
  
  # Start measurement
  producer = @tspawnat protocol.scanner.generalParams.producerThreadID performMeasurement(protocol)
  while !istaskdone(producer)
    handleEvents(protocol)
    # Dont want to throw cancel here
    sleep(0.05)
  end

  if Base.istaskfailed(producer)
    currExceptions = current_exceptions(producer)
    @error "Measurement failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions) - 1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
    throw(ex)
  end

  # Increment measured positions
  protocol.currPos +=1
end

function startMeasurement(protocol::RobotBasedTDesignFieldProtocol)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(vcat(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
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
  current = 0
  # Wait for measurement proper frame to start
  timing = getTiming(daq)
  while current < timing.start
    current = currentWP(daq.rpc)
    sleep(0.01)
  end
end

function stopMeasurement(protocol::RobotBasedTDesignFieldProtocol)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only enable amps that amplify a channel of the current sequence
    channelIdx = id.(vcat(acyclicElectricalTxChannels(protocol.params.sequence), periodicElectricalTxChannels(protocol.params.sequence)))
    amps = filter(amp -> in(channelId(amp), channelIdx), amps)
  end
  timing = getTiming(daq)
  @show timing 
  endSequence(daq, timing.finish)
  @sync for amp in amps
    @async turnOff(amp)
  end
  if !isnothing(tempControl)
    enableControl(tempControl)
  end
  if !isnothing(su)
    disableACPower(su)
  end
end

function performMeasurement(protocol::RobotBasedTDesignFieldProtocol)
  daq = getDAQ(protocol.scanner)
  startMeasurement(protocol)
  gaussmeter = getGaussMeter(scanner(protocol))
  
  field = getXYZValues(protocol, gaussmeter)
  timing = getTiming(daq)
  current = currentWP(daq.rpc)
  if current > timing.down
    @warn current
    @warn "Magnetic field was measured too late"
  end
  protocol.finalizer = @tspawnat protocol.scanner.generalParams.consumerThreadID finishMeasurement(protocol, gaussmeter, field, protocol.currPos)
end

getXYZValues(::RobotBasedTDesignFieldProtocol, gauss::GaussMeter) = getXYZValues(gauss)
function finishMeasurement(protocol::RobotBasedTDesignFieldProtocol, ::GaussMeter, field, index::Int64)
  protocol.measurement[:, protocol.indices[index]] = ustrip.(u"T", field)
  stopMeasurement(protocol)
end

getXYZValues(::RobotBasedTDesignFieldProtocol, gauss::LakeShore460GaussMeter) = getAllFields(gauss)
function finishMeasurement(protocol::RobotBasedTDesignFieldProtocol, gauss::LakeShore460GaussMeter, field, index::Int64)
  @sync begin
    @async begin 
      multipliers = getAllMultipliers(gauss, LiveMultiplier())
      field = gauss.params.coordinateTransformation*(field.*multipliers)*Unitful.T
      protocol.measurement[:, protocol.indices[index]] = ustrip.(u"T", field)
    end
    @async stopMeasurement(protocol)
  end
end

function pause(protocol::RobotBasedTDesignFieldProtocol)
  if protocol.currPos <= length(protocol.positions)
    # OperationSuccessfulEvent is put when it actually is in the stop loop
    protocol.stopped = true
  else 
    # Stopped has no concept once all measurements are done
    put!(protocol.biChannel, OperationUnsuccessfulEvent(PauseEvent()))
  end
end

function resume(protocol::RobotBasedTDesignFieldProtocol)
  protocol.stopped = false
  protocol.restored = true
  # OperationSuccessfulEvent is put when it actually leaves the stop loop
end

function cancel(protocol::RobotBasedTDesignFieldProtocol)
  protocol.cancelled = true # Set cancel s.t. exception can be thrown when appropiate
  protocol.stopped = true # Set stop to reach a known/save state
end


function handleEvent(protocol::RobotBasedTDesignFieldProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel, ProgressEvent(protocol.currPos, length(protocol.positions), "Position", event))
end

handleEvent(protocol::RobotBasedTDesignFieldProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::RobotBasedTDesignFieldProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  h5open(filename, "w") do file
    write(file,"/fields", protocol.measurement) 		# measured field (size: 3 x #points x #patches)
    write(file,"/positions/tDesign/radius", ustrip(u"m", protocol.params.radius))	# radius of the measured ball
    write(file,"/positions/tDesign/N", protocol.params.N)		# number of points of the t-design
    write(file,"/positions/tDesign/t", protocol.params.T)		# t of the t-design
    write(file,"/positions/tDesign/center", ustrip.(u"m", protocol.params.center.data))	# center of the measured ball
    write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO only works for LakeShore460 atm
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end


protocolInteractivity(protocol::RobotBasedTDesignFieldProtocol) = Interactive()
