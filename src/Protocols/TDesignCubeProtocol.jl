
export TDesignCubeProtocolParams, TDesignCubeProtocol

Base.@kwdef mutable struct TDesignCubeProtocolParams <: ProtocolParams
  sequence::Union{Sequence,Nothing} = nothing
  center::ScannerCoords = ScannerCoords([[0.0u"mm", 0.0u"mm", 0.0u"mm"]])
  samplesSize::Union{Nothing,Int64} = nothing # Optional overwrite
end
function TDesignCubeProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    dict["sequence"] = sequence
    delete!(dict, "sequence")
  end

  params = params_from_dict(TDesignCubeProtocolParams, dict)
  params.sequence = sequence
  return params

end

Base.@kwdef mutable struct TDesignCubeProtocol <: Protocol
  @add_protocol_fields TDesignCubeProtocolParams
  finishAcknowledged::Bool = false
  measurement::Union{Matrix{Float64},Nothing} = nothing
  tDesign::Union{SphericalTDesign,Nothing} = nothing
end

requiredDevices(protocol::TDesignCubeProtocol) = [TDesignCube, AbstractDAQ]

function _init(protocol::TDesignCubeProtocol)
  if isnothing(protocol.params.sequence)
    throw(IllegalStateException("Protocol requires a sequence"))
  end
  cube = getDevice(protocol.scanner, TDesignCube)
  # TODO get T, N, radius from TDesignCube
  N = getN(cube)
  T = getT(cube)
  radius = getRadius(cube)
  protocol.tDesign = loadTDesign(T, N, radius, protocol.params.center.data)
  protocol.measurement = zeros(Float64, 3, length(protocol.tDesign))
end


function enterExecute(protocol::TDesignCubeProtocol)
  protocol.finishAcknowledged = false
end

function _execute(protocol::TDesignCubeProtocol)
  @debug "TDesignCube protocol started"

  performMeasurement(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())

  debugCount = 0

  while !(protocol.finishAcknowledged)
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
  end

  @info "Protocol finished."
  close(protocol.biChannel)
  @debug "Protocol channel closed after execution."
end

function performMeasurement(protocol::TDesignCubeProtocol)
  cube = getDevice(scanner(protocol), TDesignCube)
  producer = @tspawnat protocol.scanner.generalParams.producerThreadID measurement(protocol)
  while !istaskdone(producer)
    handleEvents(protocol)
    # Dont want to throw cancel here
    sleep(0.05)
  end

  if Base.istaskfailed(producer)
    currExceptions = current_exceptions(producer)
    @error "Measurement failed" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
    for i in 1:length(currExceptions)-1
      stack = currExceptions[i]
      @error stack[:exception] trace = stacktrace(stack[:backtrace])
    end
    ex = currExceptions[1][:exception]
    throw(ex)
  end
end

function startMeasurement(protocol::TDesignCubeProtocol)
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
  while current < timing.start
    current = currentWP(daq.rpc)
    sleep(0.01)
  end
end

function stopMeasurement(protocol::TDesignCubeProtocol)
  daq = getDAQ(protocol.scanner)
  su = getSurveillanceUnit(protocol.scanner)
  tempControl = getTemperatureController(protocol.scanner)
  amps = getDevices(protocol.scanner, Amplifier)
  if !isempty(amps)
    # Only disable amps that amplify a channel of the current sequence
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

function measurement(protocol::TDesignCubeProtocol)
  daq = getDAQ(protocol.scanner)
  startMeasurement(protocol)
  cube = getDevice(scanner(protocol), TDesignCube)
  if sample_size
    setSampleSize(cube)
  end
  field = getXYZValues(protocol, cube)
  timing = getTiming(daq)
  current = currentWP(daq.rpc)
  if current > timing.down
    @warn current
    @warn "Magnetic field was measured too late"
  end
  stopMeasurement(protocol)
  protocol.measurement = ustrip.(u"T", field)
end

handleEvent(protocol::TDesignCubeProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true

function handleEvent(protocol::TDesignCubeProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  h5open(filename, "w") do file
    write(file, "/fields", protocol.measurement) # measured field (size: 3 x #points x #patches)
    # TODO get T, N, radius from TDesignCube
    write(file, "/positions/tDesign/radius", ustrip(u"m", radius))# radius of the measured ball
    write(file, "/positions/tDesign/N", N)# number of points of the t-design
    write(file, "/positions/tDesign/t", T)# t of the t-design
    write(file, "/positions/tDesign/center", ustrip.(u"m", protocol.params.center.data))# center of the measured ball
    #write(file, "/sensor/correctionTranslation", getGaussMeter(protocol.scanner).params.sensorCorrectionTranslation) # TODO Write 3x3xN rotated translations
  end
  put!(protocol.biChannel, StorageSuccessEvent(filename))
end

function cleanup(protocol::TDesignCubeProtocol)
  # NOP
end
