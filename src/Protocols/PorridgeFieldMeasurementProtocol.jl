export PorridgeFieldMeasurementProtocol, PorridgeFieldMeasurementProtocolParams

Base.@kwdef mutable struct PorridgeFieldMeasurementProtocolParams <: ProtocolParams
  sequence::Union{Sequence, Nothing} = nothing
  enableSphericalHarmonics::Bool = true
  tDesignOrder::Int64 = 12
  sphericalRadius::typeof(1.0u"m") = 0.045u"m"
end

function PorridgeFieldMeasurementProtocolParams(dict::Dict, scanner::MPIScanner)
  sequence = nothing
  if haskey(dict, "sequence")
    sequence = Sequence(scanner, dict["sequence"])
    delete!(dict, "sequence")
  end
  params = params_from_dict(PorridgeFieldMeasurementProtocolParams, dict)
  params.sequence = sequence
  return params
end

PorridgeFieldMeasurementProtocolParams(dict::Dict) =
  params_from_dict(PorridgeFieldMeasurementProtocolParams, dict)


Base.@kwdef mutable struct PorridgeFieldMeasurementProtocol <: Protocol
  @add_protocol_fields PorridgeFieldMeasurementProtocolParams

  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
  measuring::Bool = false
  unit::String = "frames"

  fieldData::Vector{FieldCameraResult} = FieldCameraResult[]
  frameMetadata::Vector{Dict{String,Any}} = Dict{String,Any}[]
  currentFrameNum::Int64 = 0
  totalFrames::Int64 = 0
end


requiredDevices(::PorridgeFieldMeasurementProtocol) = [AbstractDAQ, GaussMeter]

function _init(protocol::PorridgeFieldMeasurementProtocol)
  isnothing(protocol.params.sequence) &&
    throw(IllegalStateException("Protocol requires a sequence"))
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentFrameNum = 0
end

function timeEstimate(protocol::PorridgeFieldMeasurementProtocol)
  isnothing(protocol.params.sequence) && return "Unknown"
  # ~100 ms per triggered frame is a reasonable estimate
  return string(acqNumFrames(protocol.params.sequence) * 0.1 * 1u"s")
end

function enterExecute(protocol::PorridgeFieldMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.fieldData = FieldCameraResult[]
  protocol.frameMetadata = Dict{String,Any}[]
  protocol.currentFrameNum = 0
  if !isnothing(protocol.params.sequence)
    seq = protocol.params.sequence
    triggerPatches = computeTriggerPatches(seq)
    repetitions = acqNumFrames(seq) * acqNumFrameAverages(seq)
    protocol.totalFrames = length(triggerPatches) * repetitions
  end
end

function _execute(protocol::PorridgeFieldMeasurementProtocol)
  try
    performFieldMeasurement(protocol)
    put!(protocol.biChannel, FinishedNotificationEvent())
    while !protocol.finishAcknowledged
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
    end
  catch e
    isa(e, CancelException) && rethrow(e)
    @error "Protocol execution error" exception = e
    rethrow(e)
  end
end

cleanup(protocol::PorridgeFieldMeasurementProtocol) = nothing
stop(protocol::PorridgeFieldMeasurementProtocol) = (protocol.stopped = true)
cancel(protocol::PorridgeFieldMeasurementProtocol) = (protocol.cancelled = true)

function resume(protocol::PorridgeFieldMeasurementProtocol)
  put!(protocol.biChannel, OperationNotSupportedEvent(ResumeEvent()))
end


function computeTriggerPatches(sequence::Sequence)
  for field in fields(sequence)
    for channel in channels(field)
      if id(channel) == "trigger" && isa(channel, StepwiseElectricalChannel)
        vals = ustrip.(values(channel))
        threshold = maximum(abs.(vals)) / 2
        indices = Int[]
        prev = 0.0
        for (i, v) in enumerate(vals)
          if prev < threshold && v >= threshold
            push!(indices, i)
          end
          prev = v
        end
        return indices
      end
    end
  end
  return collect(1:acqNumPatches(sequence))
end

function getCoilCurrentsForPatch(sequence::Sequence, patchIdx::Int)
  currents = Dict{String,Float64}()
  for field in fields(sequence)
    for channel in channels(field)
      if isa(channel, StepwiseElectricalChannel)
        stepIdx = mod1(patchIdx, length(channel.values))
        currents[id(channel)] = ustrip(channel.values[stepIdx])
      end
    end
  end
  return currents
end

function performFieldMeasurement(protocol::PorridgeFieldMeasurementProtocol)
  protocol.measuring = true

  scanner_ = protocol.scanner
  daq = getDAQ(scanner_)
  cam = getGaussMeter(scanner_)
  sequence = protocol.params.sequence

  triggerPatches = computeTriggerPatches(sequence)
  repetitions = acqNumFrames(sequence) * acqNumFrameAverages(sequence)
  protocol.totalFrames = length(triggerPatches) * repetitions

  @info "Starting field measurement" triggers=length(triggerPatches) total=protocol.totalFrames

  for ch in acyclicElectricalTxChannels(sequence)
    if id(ch) == "trigger"
      numVals = length(ch.values)
      baseFreq = ustrip(u"Hz", txBaseFrequency(sequence))
      stepTime_ms = ch.divider / (numVals * baseFreq) * 1000
      gapMs = 2 * stepTime_ms
      @info "Trigger timing" step_ms=round(stepTime_ms, digits=1) gap_ms=round(gapMs, digits=1)
      gapMs < 175 && @warn "Trigger gap $(round(gapMs, digits=1)) ms < 175 ms minimum"
      break
    end
  end

  setup(daq, sequence)

  su = getSurveillanceUnits(scanner_)
  !isempty(su) && enableACPower(su[1])

  enable(cam)

  startTx(daq)
  timing = getTiming(daq)

  finish = timing.finish
  while currentWP(daq.rpc) < finish
    handleEvents(protocol)
    if protocol.cancelled || protocol.stopped
      execute!(daq.rpc) do batch
        for idx in daq.rampingChannel
          @add_batch batch enableRampDown!(daq.rpc, idx, true)
        end
      end
      while !rampDownDone(daq.rpc)
        handleEvents(protocol)
      end
      finish = currentWP(daq.rpc)
      break
    end
    sleep(0.01)
  end

  endSequence(daq, finish)
  !isempty(su) && disableACPower(su[1])

  sleep(0.5)
  results = readAllTriggeredFields(cam)

  for result in results
    length(protocol.fieldData) >= protocol.totalFrames && break
    triggerIdx = mod1(length(protocol.fieldData) + 1, length(triggerPatches))
    patchIdx = triggerPatches[triggerIdx]
    metadata = Dict{String,Any}(
      "frameIndex"     => length(protocol.fieldData) + 1,
      "patchIndex"     => patchIdx,
      "coilCurrents"   => getCoilCurrentsForPatch(sequence, patchIdx),
      "timestamp"      => result.timestamp,
      "reading_id"     => result.reading_id,
      "arduino_millis" => result.arduino_millis,
      "sensor_read_ms" => result.sensor_read_ms,
      "total_isr_ms"   => result.total_isr_ms,
    )
    push!(protocol.fieldData, result)
    push!(protocol.frameMetadata, metadata)
    protocol.currentFrameNum = length(protocol.fieldData)
    @info "Measurement $(protocol.currentFrameNum)/$(protocol.totalFrames)" reading_id=result.reading_id patch=patchIdx
  end

  if length(protocol.fieldData) < protocol.totalFrames
    @warn "Captured $(length(protocol.fieldData))/$(protocol.totalFrames) measurements"
  end

  disable(cam)
  protocol.measuring = false

  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
  end
  protocol.cancelled && throw(CancelException())

  @info "Field measurement complete" measurements=length(protocol.fieldData)
end


function handleEvent(protocol::PorridgeFieldMeasurementProtocol, event::ProgressQueryEvent)
  put!(protocol.biChannel,
    ProgressEvent(protocol.currentFrameNum, protocol.totalFrames, protocol.unit, event))
end

function handleEvent(protocol::PorridgeFieldMeasurementProtocol, event::FinishedAckEvent)
  protocol.finishAcknowledged = true
end

function handleEvent(protocol::PorridgeFieldMeasurementProtocol, event::FileStorageRequestEvent)
  filename = event.filename
  @info "Saving measurement data to $filename"
  try
    h5open(filename, "w") do file
      saveFieldCameraData(file, protocol)
      write(file, "/protocol", string(typeof(protocol)))
      write(file, "/timestamp", string(now()))
      if !isnothing(protocol.params.sequence)
        write(file, "/sequenceName", protocol.params.sequence.general.name)
      end
    end
    put!(protocol.biChannel, StorageSuccessEvent(filename))
    @info "Data saved to $filename"
  catch e
    @error "Save error" exception=e
    put!(protocol.biChannel, ExceptionEvent(e))
  end
end


function saveFieldCameraData(file, protocol::PorridgeFieldMeasurementProtocol)
  isempty(protocol.fieldData) && (@warn "No field data to save"; return)

  data = map(r -> r.data, protocol.fieldData)
  timestamps = map(r -> r.timestamp, protocol.fieldData)

  dataArray = cat(data..., dims=3)

  write(file, "/sensorData", ustrip.(u"T", dataArray))
  write(file, "/timestamps", timestamps)
  write(file, "/numSensors", size(dataArray, 2))
  write(file, "/numMeasurements", size(dataArray, 3))

  if !isempty(protocol.frameMetadata)
    try
      frameIndices = [m["frameIndex"] for m in protocol.frameMetadata]
      write(file, "/frameIndices", frameIndices)

      if haskey(protocol.frameMetadata[1], "patchIndex")
        patchIndices = [m["patchIndex"] for m in protocol.frameMetadata]
        write(file, "/patchIndices", patchIndices)
      end

      coilNames = sort(collect(keys(protocol.frameMetadata[1]["coilCurrents"])))
      numCoils = length(coilNames)
      coilMatrix = zeros(Float64, length(protocol.frameMetadata), numCoils)
      for (i, m) in enumerate(protocol.frameMetadata)
        for (j, name) in enumerate(coilNames)
          coilMatrix[i, j] = get(m["coilCurrents"], name, 0.0)
        end
      end
      write(file, "/coilCurrents", coilMatrix)
      write(file, "/coilNames", coilNames)
    catch e
      @warn "Could not save frame metadata" exception = e
    end
  end

  try
    write(file, "/sensorPositions", getSensorPositions())
  catch e
    @warn "Could not save sensor positions" exception = e
  end

  if protocol.params.enableSphericalHarmonics
    processSphericalHarmonics(file, protocol, dataArray)
  end
end

function processSphericalHarmonics(file, protocol::PorridgeFieldMeasurementProtocol, dataArray)
  if !isdefined(Main, :MPISphericalHarmonics) || !isdefined(Main, :MPIUI)
    @debug "Spherical harmonics skipped (MPISphericalHarmonics / MPIUI not loaded)"
    return
  end

  try
    radius = protocol.params.sphericalRadius
    T = protocol.params.tDesignOrder
    N = size(dataArray, 2)

    tDes = Main.MPIUI.loadTDesign(T, N, radius)

    coeffsArray = []
    for i in 1:size(dataArray, 3)
      frame = dataArray[:, :, i]
      coeffs = Main.MPIUI.MagneticFieldCoefficients(
        Main.MPISphericalHarmonics.magneticField(tDes, ustrip.(u"T", frame)),
        ustrip(radius),
      )
      push!(coeffsArray, coeffs)
    end

    write(file, "/sphericalHarmonics/tDesignOrder", T)
    write(file, "/sphericalHarmonics/radius", ustrip(u"m", radius))
    write(file, "/sphericalHarmonics/numCoeffs", length(coeffsArray))

    @info "Spherical harmonics: $(length(coeffsArray)) frames processed"
  catch e
    @warn "Spherical harmonics processing failed" exception = e
  end
end
