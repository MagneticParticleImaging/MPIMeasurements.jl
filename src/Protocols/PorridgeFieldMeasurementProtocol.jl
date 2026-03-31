export PorridgeFieldMeasurementProtocol, PorridgeFieldMeasurementProtocolParams

function plotFieldDiagnostics(fields::Matrix{Float64}, positions::Matrix{Float64};
                              filename::Union{String,Nothing}=nothing)
  N = size(fields, 2)
  @assert size(fields, 1) == 3
  @assert size(positions) == (3, N)

  Bmag = [norm(fields[:, i]) for i in 1:N]  # field magnitude per sensor
  pos_mm = positions  # assumed in mm

  fig = Figure(size=(1400, 1000), fontsize=14)

  # ── Panel 1: field magnitude at each sensor position (3 projections) ──
  projections = [("XY plane", 1, 2), ("XZ plane", 1, 3), ("YZ plane", 2, 3)]
  for (k, (title, ax1, ax2)) in enumerate(projections)
    ax = Axis(fig[1, k]; title, xlabel="$(["x","y","z"][ax1]) / mm",
              ylabel="$(["x","y","z"][ax2]) / mm", aspect=DataAspect())
    sc = scatter!(ax, pos_mm[ax1, :], pos_mm[ax2, :]; color=Bmag .* 1e3,
                  colormap=:viridis, markersize=14)
    # Draw field arrows (scaled for visibility)
    scale = 0.4 * maximum(abs.(pos_mm)) / maximum(Bmag .+ eps())
    arrows!(ax, pos_mm[ax1, :], pos_mm[ax2, :],
            fields[ax1, :] .* scale, fields[ax2, :] .* scale;
            color=:white, linewidth=1.5, arrowsize=6)
    Colorbar(fig[1, k+3]; colormap=:viridis, limits=extrema(Bmag .* 1e3),
             label="|B| / mT", vertical=true, width=12)
    k < 3 && hideydecorations!(ax; label=false, ticklabels=false)
  end

  # ── Panel 2: Bx, By, Bz per sensor index ──
  ax2 = Axis(fig[2, 1:3]; xlabel="Sensor index", ylabel="B / mT",
             title="Field components per sensor")
  barplot!(ax2, 1:N, fields[1, :] .* 1e3; color=:steelblue, label="Bx",
           dodge=repeat([1], N), width=0.25, offset=-0.25)
  barplot!(ax2, 1:N, fields[2, :] .* 1e3; color=:forestgreen, label="By",
           dodge=repeat([2], N), width=0.25, offset=0.0)
  barplot!(ax2, 1:N, fields[3, :] .* 1e3; color=:goldenrod, label="Bz",
           dodge=repeat([3], N), width=0.25, offset=0.25)
  axislegend(ax2; position=:rt)
  hlines!(ax2, [0.0]; color=:gray50, linestyle=:dash)

  # ── Panel 3: |B| vs radial angle from x-axis ──
  ax3 = Axis(fig[3, 1:3]; xlabel="Angle from +x axis / °", ylabel="|B| / mT",
             title="Field magnitude vs angle from +x (expect V-shape for FFP along x)")
  angles = [acosd(pos_mm[1, i] / norm(pos_mm[:, i])) for i in 1:N]
  scatter!(ax3, angles, Bmag .* 1e3; color=:steelblue, markersize=10)
  # Also show components projected onto radial direction
  Bradial = [dot(fields[:, i], pos_mm[:, i]) / norm(pos_mm[:, i]) for i in 1:N]
  scatter!(ax3, angles, abs.(Bradial) .* 1e3; color=:tomato, markersize=8,
           marker=:utriangle, label="|B_radial|")
  axislegend(ax3; position=:rt)

  if !isnothing(filename)
    save(filename, fig; px_per_unit=2)
    @info "Diagnostic plot saved to $filename"
  end

  return fig
end

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
  coilTemperatureData::Vector{Vector{Float64}} = Vector{Float64}[]
  currentFrameNum::Int64 = 0
  totalFrames::Int64 = 0
  lastReadingId::Int64 = -1
end


requiredDevices(::PorridgeFieldMeasurementProtocol) = [AbstractDAQ, GaussMeter, TemperatureSensor]

function _init(protocol::PorridgeFieldMeasurementProtocol)
  isnothing(protocol.params.sequence) &&
    throw(IllegalStateException("Protocol requires a sequence"))
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
  protocol.currentFrameNum = 0
  protocol.lastReadingId = -1
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
  protocol.coilTemperatureData = Vector{Float64}[]
  protocol.currentFrameNum = 0
  protocol.lastReadingId = -1
  if !isnothing(protocol.params.sequence)
    seq = protocol.params.sequence
    triggerPatches = computeTriggerPatches(seq)
    repetitions = acqNumFrames(seq) * acqNumFrameAverages(seq)
    protocol.totalFrames = length(triggerPatches) * repetitions
  end
end

function appendTriggeredResults!(protocol::PorridgeFieldMeasurementProtocol,
                                sequence::Sequence,
                                triggerPatches::Vector{Int},
                                results::Vector{FieldCameraResult};
                                coilTemperatures::Vector{Float64}=Float64[])
  for result in results
    protocol.currentFrameNum >= protocol.totalFrames && break

    delta = 1
    if protocol.lastReadingId >= 0 && result.reading_id >= 0
      delta = mod(result.reading_id - protocol.lastReadingId, 256)
      if delta == 0
        continue
      elseif delta > 1
        @warn "Dropped triggered readings detected" missing=(delta - 1) previous=protocol.lastReadingId current=result.reading_id
      end
    end

    frameIndex = protocol.currentFrameNum + max(delta, 1)
    frameIndex > protocol.totalFrames && break

    triggerIdx = mod1(frameIndex, length(triggerPatches))
    patchIdx = triggerPatches[triggerIdx]
    metadata = Dict{String,Any}(
      "frameIndex"     => frameIndex,
      "patchIndex"     => patchIdx,
      "coilCurrents"   => getCoilCurrentsForPatch(sequence, patchIdx),
      "timestamp"      => result.timestamp,
      "reading_id"     => result.reading_id,
      "arduino_millis" => result.arduino_millis,
      "sensor_read_ms" => result.sensor_read_ms,
      "total_isr_ms"   => result.total_isr_ms,
      "coil_temperatures" => coilTemperatures,
    )

    push!(protocol.fieldData, result)
    push!(protocol.frameMetadata, metadata)
    push!(protocol.coilTemperatureData, copy(coilTemperatures))
    protocol.currentFrameNum = frameIndex
    protocol.lastReadingId = result.reading_id

    @info "Measurement $(protocol.currentFrameNum)/$(protocol.totalFrames)" reading_id=result.reading_id patch=patchIdx
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

function _temperatureToCelsius(value)
  try
    return ustrip(u"°C", value)
  catch
    try
      return Float64(value)
    catch
      return NaN
    end
  end
end

function readCoilTemperatures(sensor::TemperatureSensor)
  temps = try
    getTemperatures(sensor)
  catch e
    throw(IllegalStateException("Failed to read coil temperatures from TemperatureSensor: $(typeof(e))"))
  end

  isempty(temps) && throw(IllegalStateException("TemperatureSensor returned zero coil temperature channels"))

  values = Float64[]
  for t in temps
    push!(values, _temperatureToCelsius(t))
  end

  maxTemps = try
    Float64.(sensor.params.maxTemps)
  catch
    Float64[]
  end

  n = min(length(values), length(maxTemps))
  for idx in 1:n
    if values[idx] > maxTemps[idx]
      return values, true, idx, values[idx], maxTemps[idx]
    end
  end

  return values, false, 0, NaN, NaN
end

function coilTemperatureMatrix(trace::Vector{Vector{Float64}})
  isempty(trace) && return fill(NaN, 0, 0)
  maxChannels = maximum(length, trace)
  maxChannels == 0 && throw(IllegalStateException("No coil temperature channels captured; cannot save coil temperature matrix"))
  numFrames = length(trace)
  mat = fill(NaN, maxChannels, numFrames)
  for frame in 1:numFrames
    vals = trace[frame]
    for ch in eachindex(vals)
      mat[ch, frame] = vals[ch]
    end
  end
  return mat
end

function coilCurrentMatrix(frameMetadata::Vector{Dict{String,Any}})
  isempty(frameMetadata) && return String[], fill(NaN, 0, 0)

  channelNames = String[]
  for meta in frameMetadata
    currents = get(meta, "coilCurrents", Dict{String,Float64}())
    for key in keys(currents)
      startswith(key, "coil") && push!(channelNames, key)
    end
  end

  channelNames = unique(sort(channelNames))
  isempty(channelNames) && return String[], fill(NaN, 0, length(frameMetadata))

  indexByChannel = Dict(name => idx for (idx, name) in enumerate(channelNames))
  mat = fill(NaN, length(channelNames), length(frameMetadata))

  for (frameIdx, meta) in enumerate(frameMetadata)
    currents = get(meta, "coilCurrents", Dict{String,Float64}())
    for (channel, value) in currents
      startswith(channel, "coil") || continue
      channelIdx = indexByChannel[channel]
      mat[channelIdx, frameIdx] = Float64(value)
    end
  end

  return channelNames, mat
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
      @info "Trigger timing" step_ms=round(stepTime_ms, digits=1)
      break
    end
  end

  setup(daq, sequence)
  tempSensor = getTemperatureSensor(scanner_)

  enable(cam)

  coilTemperatures, overheat, overheatCoil, overheatTemp, overheatMax = readCoilTemperatures(tempSensor)
  if overheat
    @error "Overheat detected before sequence start" coil=overheatCoil temperature=overheatTemp max=overheatMax
    disable(cam)
    protocol.measuring = false
    return
  end

  startTx(daq)
  timing = getTiming(daq)

  finish = timing.finish
  while currentWP(daq.rpc) < finish
    coilTemperatures, overheat, overheatCoil, overheatTemp, overheatMax = readCoilTemperatures(tempSensor)
    if overheat
      @error "Overheat detected, stopping protocol early" coil=overheatCoil temperature=overheatTemp max=overheatMax
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

    appendTriggeredResults!(protocol, sequence, triggerPatches,
                            pollTriggeredFields(cam; timeout_ms=5, maxReads=2);
                            coilTemperatures)
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

  idlePolls = 0
  while protocol.currentFrameNum < protocol.totalFrames && idlePolls < 40
    before = protocol.currentFrameNum
    coilTemperatures, overheat, overheatCoil, overheatTemp, overheatMax = readCoilTemperatures(tempSensor)
    if overheat
      @error "Overheat detected during tail capture, stopping capture" coil=overheatCoil temperature=overheatTemp max=overheatMax
      break
    end

    appendTriggeredResults!(protocol, sequence, triggerPatches,
                            pollTriggeredFields(cam; timeout_ms=50, maxReads=1);
                            coilTemperatures)
    idlePolls = protocol.currentFrameNum == before ? idlePolls + 1 : 0
  end

  if protocol.currentFrameNum < protocol.totalFrames
    @warn "Captured $(length(protocol.fieldData)) results for $(protocol.currentFrameNum)/$(protocol.totalFrames) expected trigger indices"
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

  nFrames = length(protocol.fieldData)
  nSensors = length(FC_TDESIGN_REORDER)
  positions_mm = getSensorPositions()[:, FC_TDESIGN_REORDER]*0.001/0.037

  currentChannelNames, currentMatrix = coilCurrentMatrix(protocol.frameMetadata)

  write(file, "/positions/tDesign/radius", 0.037)
  write(file, "/positions/tDesign/N", 36)
  write(file, "/positions/tDesign/t", 8)
  write(file, "/positions/tDesign/center", [0.0, 0.0, 0.0])
  write(file, "/positions/tDesign/positions", positions_mm)
  write(file, "/sensor/correctionTranslation", [0.0 0.0 0.0; 0.0 0.0 0.0; 0.0 0.0 0.0])
  write(file, "/currents/coil/channel_names", currentChannelNames)
  write(file, "/currents/coil/value", currentMatrix)
  write(file, "/temperature/coil/value", coilTemperatureMatrix(protocol.coilTemperatureData))
  write(file, "/temperature/unit", "°C")

  fields = Array{Float64}(undef, 3, nSensors, nFrames)
  R = [-1.0 0.0 0.0; 0.0 0.0 1.0; 0.0 -1.0 0.0]
  @info "Converting field frames for HDF5" frames=nFrames
  for frameIdx in 1:nFrames
    raw = ustrip.(u"T", protocol.fieldData[frameIdx].data[:, FC_TDESIGN_REORDER])
    fields[:, :, frameIdx] .= R * raw
  end

  write(file, "/fields", fields)
end