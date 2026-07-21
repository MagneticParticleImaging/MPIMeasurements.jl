export PorridgeFieldMeasurementProtocol, PorridgeFieldMeasurementProtocolParams

using DelimitedFiles

const RIGHT_COIL_ORDER = [17, 3, 18, 14, 12, 16, 10, 11, 13]
const LEFT_COIL_ORDER = [9, 6, 8, 7, 15, 5, 4, 2, 1]

const RIGHT_COIL_POSITIONS = Dict(coil => pos for (pos, coil) in enumerate(RIGHT_COIL_ORDER))
const LEFT_COIL_POSITIONS = Dict(coil => pos for (pos, coil) in enumerate(LEFT_COIL_ORDER))

function coilChannelLabel(coilID::Int)
  if haskey(RIGHT_COIL_POSITIONS, coilID)
    return "coil$(coilID)_R$(RIGHT_COIL_POSITIONS[coilID])"
  elseif haskey(LEFT_COIL_POSITIONS, coilID)
    return "coil$(coilID)_L$(LEFT_COIL_POSITIONS[coilID])"
  else
    return "coil$(coilID)"
  end
end

function coilChannelSortKey(name::AbstractString)
  m = match(r"^coil(\d+)$", name)
  if isnothing(m)
    return typemax(Int)
  end
  return parse(Int, m.captures[1])
end

function labeledCoilChannelName(name::AbstractString)
  m = match(r"^coil(\d+)$", name)
  if isnothing(m)
    return String(name)
  end
  return coilChannelLabel(parse(Int, m.captures[1]))
end

function waitForCoilCooling(sensor::TemperatureSensor, overheatCoilIdx::Int; cooldownTemp::Float64=45.0, maxWaitTime_s::Float64=3600.0)
  startTime = time()
  while time() - startTime < maxWaitTime_s
    try
      temps = getTemperatures(sensor)
      if overheatCoilIdx <= length(temps)
        coilTemp = _temperatureToCelsius(temps[overheatCoilIdx])
        if coilTemp < cooldownTemp
          @info "Coil cooldown complete" coil_label=coilChannelLabel(overheatCoilIdx) temperature=round(coilTemp, digits=1)
          return true
        end
        @info "Waiting for coil cooldown" coil_label=coilChannelLabel(overheatCoilIdx) current_temp=round(coilTemp, digits=1) target_temp=cooldownTemp elapsed_s=round(time() - startTime, digits=1)
      end
    catch e
      @warn "Error reading temperature during cooldown wait" exception=e
    end
    sleep(5.0)  # Check every 5 seconds
  end
  @warn "Cooldown wait timeout reached" coil_label=coilChannelLabel(overheatCoilIdx) max_wait_s=maxWaitTime_s
  return false
end

function sliceSequenceFromStep(sequence::Sequence, startStep::Int)
  newFields = MagneticField[]
  for field in fields(sequence)
    newChannels = TxChannel[]
    for channel in channels(field)
      if isa(channel, StepwiseElectricalChannel)
        slicedValues = channel.values[startStep:end]
        slicedEnable = isempty(channel.enable) ? channel.enable : channel.enable[startStep:end]
        push!(newChannels, StepwiseElectricalChannel(
          id=channel.id,
          divider=channel.divider,
          values=slicedValues,
          enable=slicedEnable,
        ))
      else
        push!(newChannels, channel)
      end
    end
    push!(newFields, MagneticField(
      id=field.id,
      channels=newChannels,
      safeStartInterval=field.safeStartInterval,
      safeTransitionInterval=field.safeTransitionInterval,
      safeEndInterval=field.safeEndInterval,
      safeErrorInterval=field.safeErrorInterval,
      control=field.control,
      decouple=field.decouple,
    ))
  end
  return Sequence(general=sequence.general, fields=newFields, acquisition=sequence.acquisition)
end

function rampDownAndWait!(daq, protocol)
  execute!(daq.rpc) do batch
    for idx in daq.rampingChannel
      @add_batch batch enableRampDown!(daq.rpc, idx, true)
    end
  end
  while !rampDownDone(daq.rpc)
    handleEvents(protocol)
  end
end

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
  statusReportInterval::Int64 = 10_000
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
  
  overheatOccurred::Bool = false
  overheatFrame::Int64 = -1
  overheatCoilID::Int64 = -1
  overheatFrames::Vector{Int64} = Int64[]
  overheatCoilIDs::Vector{Int64} = Int64[]
  overheatTemps::Vector{Float64} = Float64[]

  streamCsvPath::Union{String,Nothing} = nothing
  streamCsvHandle::Union{IOStream,Nothing} = nothing
  requestedOutputPath::Union{String,Nothing} = nothing

  # Coil currents are constant for many consecutive frames (held per patch for
  # repeatsPerPair repetitions); caching the serialized CSV field by patchIdx
  # avoids rebuilding an identical Dict + String on every single frame.
  coilCurrentsCache::Dict{Int,String} = Dict{Int,String}()

  # Anchors for the periodic GC/heap diagnostic in appendTriggeredResults!.
  runStartTimeNs::UInt64 = UInt64(0)
  runStartGcTimeNs::UInt64 = UInt64(0)
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
  protocol.requestedOutputPath = nothing
  closeStreamingCsv!(protocol)
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
  protocol.overheatOccurred = false
  protocol.overheatFrame = -1
  protocol.overheatCoilID = -1
  empty!(protocol.overheatFrames)
  empty!(protocol.overheatCoilIDs)
  empty!(protocol.overheatTemps)
  empty!(protocol.coilCurrentsCache)
  protocol.runStartTimeNs = time_ns()
  protocol.runStartGcTimeNs = Base.gc_time_ns()
  protocol.requestedOutputPath = nothing
  closeStreamingCsv!(protocol)
  if !isnothing(protocol.params.sequence)
    seq = protocol.params.sequence
    triggerPatches = computeTriggerPatches(seq)
    repetitions = acqNumFrames(seq) * acqNumFrameAverages(seq)
    protocol.totalFrames = length(triggerPatches) * repetitions

    # Reduce reallocations during very long runs.
    sizehint!(protocol.fieldData, protocol.totalFrames)
    sizehint!(protocol.frameMetadata, protocol.totalFrames)
    sizehint!(protocol.coilTemperatureData, protocol.totalFrames)
    sizehint!(protocol.overheatFrames, min(protocol.totalFrames, 16))
    sizehint!(protocol.overheatCoilIDs, min(protocol.totalFrames, 16))
    sizehint!(protocol.overheatTemps, min(protocol.totalFrames, 16))
  end
  prepareStreamingCsv!(protocol)
end

function recordOverheat!(protocol::PorridgeFieldMeasurementProtocol, frame::Int64, coilID::Int64, temp::Float64)
  protocol.overheatOccurred = true
  protocol.overheatFrame = frame
  protocol.overheatCoilID = coilID
  push!(protocol.overheatFrames, frame)
  push!(protocol.overheatCoilIDs, coilID)
  push!(protocol.overheatTemps, temp)
end

function appendTriggeredResults!(protocol::PorridgeFieldMeasurementProtocol,
                                sequence::Sequence,
                                triggerPatches::Vector{Int},
                                results::Vector{FieldCameraResult};
                                coilTemperatures::Vector{Float64}=Float64[])

  # coilTemperatures is a single snapshot shared by every frame processed in
  # this call; serialize it once instead of on every frame below.
  coilTemperaturesSerialized = serializeCoilTemperatures(coilTemperatures)

  function appendFrame!(result::FieldCameraResult, frameIndex::Int; dropped::Bool=false)
    triggerIdx = mod1(frameIndex, length(triggerPatches))
    patchIdx = triggerPatches[triggerIdx]
    coilCurrentsSerialized = cachedSerializedCoilCurrents!(protocol, sequence, patchIdx)
    appendFrameToStreamingCsv!(protocol, result, frameIndex;
                                patchIdx,
                                coilCurrentsSerialized,
                                coilTemperaturesSerialized,
                                dropped,
                                tailFill=false,
                                overheatOccurred=protocol.overheatOccurred,
                                overheatFrame=protocol.overheatFrame,
                                overheatCoil=protocol.overheatCoilID)
    protocol.currentFrameNum = frameIndex
  end

  nanDataTemplate = fill(NaN, 3, 0) .* u"T"

  for result in results
    protocol.currentFrameNum >= protocol.totalFrames && break

    nanDataTemplate = result.data

    delta = 1
    if protocol.lastReadingId >= 0 && result.reading_id >= 0
      delta = mod(result.reading_id - protocol.lastReadingId, 256)
      if delta == 0
        continue
      elseif delta > 1
        @warn "Dropped triggered readings detected" missing=(delta - 1) previous=protocol.lastReadingId current=result.reading_id

        for missingIdx in 1:(delta - 1)
          frameIndex = protocol.currentFrameNum + 1
          frameIndex > protocol.totalFrames && break

          expectedReadingId = mod(protocol.lastReadingId + 1, 256)
          missingResult = FieldCameraResult(
            NaN,
            fill(NaN, size(nanDataTemplate)) .* u"T",
            expectedReadingId,
            -1,
            -1,
            -1,
          )
          appendFrame!(missingResult, frameIndex; dropped=true)
          protocol.lastReadingId = expectedReadingId
        end
      end
    end

    frameIndex = protocol.currentFrameNum + 1
    frameIndex > protocol.totalFrames && break

    appendFrame!(result, frameIndex; dropped=false)
    protocol.lastReadingId = result.reading_id

    reportEvery = protocol.params.statusReportInterval
    if reportEvery > 0 && protocol.currentFrameNum % reportEvery == 0
      elapsedNs = time_ns() - protocol.runStartTimeNs
      gcElapsedNs = Base.gc_time_ns() - protocol.runStartGcTimeNs
      gcPercent = elapsedNs > 0 ? round(gcElapsedNs / elapsedNs * 100, digits=2) : 0.0
      @info "Measurement $(protocol.currentFrameNum)/$(protocol.totalFrames)" reading_id=result.reading_id dropped=false gc_time_pct=gcPercent live_heap_mb=round(Base.gc_live_bytes() / 2^20, digits=1) rss_mb=round(Sys.maxrss() / 2^20, digits=1) rawbuffer_bytes=length(getGaussMeter(protocol.scanner).rawBuffer)
    end
  end
end

function appendMissingTailResults!(protocol::PorridgeFieldMeasurementProtocol,
                                   sequence::Sequence,
                                   triggerPatches::Vector{Int},
                                   numSensors::Int;
                                   coilTemperatures::Vector{Float64}=Float64[])
  missingFrames = protocol.totalFrames - protocol.currentFrameNum
  missingFrames <= 0 && return 0

  # coilTemperatures is constant across this whole tail-fill; serialize once.
  coilTemperaturesSerialized = serializeCoilTemperatures(coilTemperatures)

  for _ in 1:missingFrames
    frameIndex = protocol.currentFrameNum + 1
    triggerIdx = mod1(frameIndex, length(triggerPatches))
    patchIdx = triggerPatches[triggerIdx]

    expectedReadingId = protocol.lastReadingId >= 0 ? mod(protocol.lastReadingId + 1, 256) : -1
    missingResult = FieldCameraResult(
      NaN,
      fill(NaN, 3, numSensors) .* u"T",
      expectedReadingId,
      -1,
      -1,
      -1,
    )

    coilCurrentsSerialized = cachedSerializedCoilCurrents!(protocol, sequence, patchIdx)
    appendFrameToStreamingCsv!(protocol, missingResult, frameIndex;
                                patchIdx,
                                coilCurrentsSerialized,
                                coilTemperaturesSerialized,
                                dropped=true,
                                tailFill=true,
                                overheatOccurred=protocol.overheatOccurred,
                                overheatFrame=protocol.overheatFrame,
                                overheatCoil=protocol.overheatCoilID)
    protocol.currentFrameNum = frameIndex
    protocol.lastReadingId = expectedReadingId
  end

  @warn "Tail frames missing from stream; filled with NaN placeholders" missing=missingFrames
  return missingFrames
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

cleanup(protocol::PorridgeFieldMeasurementProtocol) = closeStreamingCsv!(protocol)
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

# Coil currents (and therefore their serialized CSV form) only change when
# patchIdx changes, which happens once every repeatsPerPair frames, not every
# frame. Recomputing the Dict + sorted/joined String on every single row was
# pure allocation churn sustained for the whole (multi-hour, multi-hundred-
# thousand-frame) run.
function cachedSerializedCoilCurrents!(protocol::PorridgeFieldMeasurementProtocol,
                                        sequence::Sequence, patchIdx::Int)
  return get!(protocol.coilCurrentsCache, patchIdx) do
    serializeCoilCurrents(getCoilCurrentsForPatch(sequence, patchIdx))
  end
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

  channelNames = unique(channelNames)
  sort!(channelNames; by=coilChannelSortKey)
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

  if repetitions != 1
    @warn "Overheat resume assumes a single sequence repetition" repetitions
  end

  tempSensor = getTemperatureSensor(scanner_)
  enable(cam)

  coilTemperatures, _, _, _, _ = readCoilTemperatures(tempSensor)
  tempCheckInterval = 0.2
  outcome = :complete

  while true
    runSequence = protocol.currentFrameNum == 0 ? sequence :
                  sliceSequenceFromStep(sequence, 2 * protocol.currentFrameNum + 1)
    setup(daq, runSequence)
    startTx(daq)
    finish = getTiming(daq).finish

    overheated = false
    nextTempCheck = time()
    while currentWP(daq.rpc) < finish
      if time() >= nextTempCheck
        nextTempCheck = time() + tempCheckInterval
        coilTemperatures, overheat, overheatCoil, overheatTemp, overheatMax = readCoilTemperatures(tempSensor)
        #@info coilTemperatures tempSensor.params.maxTemps
        if overheat
          recordOverheat!(protocol, protocol.currentFrameNum, overheatCoil, overheatTemp)
          @warn "Overheat detected, ramping down to cool" coil_label=coilChannelLabel(overheatCoil) temperature=round(overheatTemp, digits=1) max=overheatMax frame=protocol.currentFrameNum
          rampDownAndWait!(daq, protocol)
          finish = currentWP(daq.rpc)
          overheated = true
          break
        end
      end

      appendTriggeredResults!(protocol, sequence, triggerPatches,
                              pollTriggeredFields(cam; timeout_ms=2, maxReads=8);
                              coilTemperatures)
      handleEvents(protocol)
      if protocol.cancelled || protocol.stopped
        rampDownAndWait!(daq, protocol)
        finish = currentWP(daq.rpc)
        outcome = :stopped
        break
      end
    end

    endSequence(daq, finish)

    idlePolls = 0
    while protocol.currentFrameNum < protocol.totalFrames && idlePolls < 40
      before = protocol.currentFrameNum
      appendTriggeredResults!(protocol, sequence, triggerPatches,
                              pollTriggeredFields(cam; timeout_ms=10, maxReads=8);
                              coilTemperatures)
      idlePolls = protocol.currentFrameNum == before ? idlePolls + 1 : 0
    end

    if outcome == :stopped || protocol.currentFrameNum >= protocol.totalFrames
      break
    elseif overheated
      coil = coilChannelLabel(protocol.overheatCoilID)
      @info "Waiting for $coil to cool down before resuming" frame=protocol.currentFrameNum
      if !waitForCoilCooling(tempSensor, protocol.overheatCoilID)
        outcome = :cooldownTimeout
        break
      end
      @info "Resuming measurement" frame=protocol.currentFrameNum
    else
      break
    end
  end

  if outcome == :complete && protocol.currentFrameNum < protocol.totalFrames
    appendMissingTailResults!(protocol, sequence, triggerPatches, cam.params.numSensors;
                              coilTemperatures)
  end

  disable(cam)
  protocol.measuring = false

  if protocol.stopped
    put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
  end
  protocol.cancelled && throw(CancelException())

  @info "Field measurement complete" measurements=protocol.currentFrameNum frames_acquired=protocol.currentFrameNum target=protocol.totalFrames
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
  protocol.requestedOutputPath = filename
  @info "Saving measurement data to $filename"
  try
    prepareStreamingCsv!(protocol; requestedOutputPath=filename)
    closeStreamingCsv!(protocol)
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


function parseCoilCurrentsString(value::AbstractString)
  currentDict = Dict{String,Float64}()
  isempty(strip(value)) && return currentDict
  for entry in split(value, ";")
    isempty(strip(entry)) && continue
    name, rawValue = split(entry, "="; limit=2)
    currentDict[String(strip(name))] = parse(Float64, strip(rawValue))
  end
  return currentDict
end

function parseFloatArrayString(value::AbstractString)
  isempty(strip(value)) && return Float64[]
  return parse.(Float64, split(value, ";"))
end

function tDesignFieldMatrix(values::Vector{Float64})
  nSensorsIn = div(length(values), 3)
  nSensorsIn * 3 == length(values) ||
    throw(ArgumentError("Expected a multiple of 3 field values, got $(length(values))"))

  raw = reshape(values, 3, nSensorsIn)
  maxTDesignIndex = maximum(FC_TDESIGN_REORDER)
  nSensorsIn >= maxTDesignIndex ||
    throw(ArgumentError("Field payload has $(nSensorsIn) sensors, but t-design reordering needs at least $(maxTDesignIndex)"))

  return raw[:, FC_TDESIGN_REORDER]
end

function saveFieldCameraData(file, protocol::PorridgeFieldMeasurementProtocol)
  csvPath = protocol.streamCsvPath
  if isnothing(csvPath) || !isfile(csvPath)
    @warn "No streamed CSV file available; nothing to save"
    return
  end

  data, header = readdlm(csvPath, ',', String; header=true, skipblanks=true)
  if isempty(data)
    @warn "No field data to save"
    return
  end

  headerNames = vec(header)
  colIndex = Dict(name => idx for (idx, name) in enumerate(headerNames))

  frameMetadata = Dict{String,Any}[]
  coilTemperatureTrace = Vector{Float64}[]
  fieldValues = Vector{Vector{Float64}}()

  nFrames = size(data, 1)
  for rowIdx in 1:nFrames
    row = vec(data[rowIdx, :])
    fieldPayload = row[colIndex["field_values"]]
    parsedFieldValues = parseFloatArrayString(fieldPayload)
    if isempty(parsedFieldValues)
      continue
    end

    fieldValuesRow = parsedFieldValues
    push!(fieldValues, fieldValuesRow)

    coilCurrents = parseCoilCurrentsString(row[colIndex["coil_currents"]])
    push!(frameMetadata, Dict{String,Any}("coilCurrents" => coilCurrents))

    temperatures = parseFloatArrayString(row[colIndex["coil_temperatures"]])
    push!(coilTemperatureTrace, temperatures)
  end

  if isempty(fieldValues)
    @warn "No field data rows found in streamed CSV"
    return
  end

  nFrames = length(fieldValues)
  nSensors = length(FC_TDESIGN_REORDER)
  positions_mm = getSensorPositions()[:, FC_TDESIGN_REORDER] * 0.001 / 0.037

  currentChannelNames, currentMatrix = coilCurrentMatrix(frameMetadata)
  temperatureMatrix = coilTemperatureMatrix(coilTemperatureTrace)

  write(file, "/positions/tDesign/radius", 0.037)
  write(file, "/positions/tDesign/N", 36)
  write(file, "/positions/tDesign/t", 8)
  write(file, "/positions/tDesign/center", [0.0, 0.0, 0.0])
  write(file, "/positions/tDesign/positions", positions_mm)
  write(file, "/sensor/correctionTranslation", [0.0 0.0 0.0; 0.0 0.0 0.0; 0.0 0.0 0.0])
  write(file, "/currents/coil/channel_names", labeledCoilChannelName.(currentChannelNames))
  write(file, "/currents/coil/value", currentMatrix)
  write(file, "/temperature/coil/value", temperatureMatrix)
  write(file, "/temperature/unit", "°C")

  if protocol.overheatOccurred
    write(file, "/measurement/overheat_occurred", true)
    write(file, "/measurement/overheat_frame", protocol.overheatFrame)
    write(file, "/measurement/overheat_coil_id", protocol.overheatCoilID)
    write(file, "/measurement/overheat_coil_label", coilChannelLabel(protocol.overheatCoilID))
    write(file, "/measurement/overheat_frames", protocol.overheatFrames)
    write(file, "/measurement/overheat_coil_ids", protocol.overheatCoilIDs)
    write(file, "/measurement/overheat_temps", protocol.overheatTemps)
    write(file, "/measurement/overheat_coil_labels", coilChannelLabel.(protocol.overheatCoilIDs))
  else
    write(file, "/measurement/overheat_occurred", false)
  end

  fields = Array{Float64}(undef, 3, nSensors, nFrames)
  R = [-1.0 0.0 0.0; 0.0 0.0 1.0; 0.0 -1.0 0.0]
  @info "Converting field frames for HDF5" frames=nFrames
  for frameIdx in 1:nFrames
    values = fieldValues[frameIdx]
    raw = tDesignFieldMatrix(values)
    fields[:, :, frameIdx] .= R * raw
  end

  write(file, "/fields", fields)
end

function closeStreamingCsv!(protocol::PorridgeFieldMeasurementProtocol)
  if !isnothing(protocol.streamCsvHandle)
    close(protocol.streamCsvHandle)
    protocol.streamCsvHandle = nothing
  end
end

function prepareStreamingCsv!(protocol::PorridgeFieldMeasurementProtocol; requestedOutputPath::Union{String,Nothing}=nothing)
  if !isnothing(protocol.streamCsvHandle)
    return protocol.streamCsvPath
  end

  outputBasePath = if !isnothing(requestedOutputPath)
    requestedOutputPath
  elseif !isnothing(protocol.requestedOutputPath)
    protocol.requestedOutputPath
  else
    nothing
  end

  outputDir = if !isnothing(outputBasePath)
    dirname(abspath(expanduser(outputBasePath)))
  else
    store = expanduser(protocol.scanner.generalParams.datasetStore)
    mkpath(store)
    store
  end
  mkpath(outputDir)

  timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
  csvPath = joinpath(outputDir, "measurement_$(timestamp)_stream.csv")
  protocol.streamCsvPath = csvPath
  protocol.streamCsvHandle = open(csvPath, "a", lock=false)  # disable lock to avoid contention; single writer

  header = [
    "frameIndex",
    "patchIndex",
    "reading_id",
    "timestamp",
    "arduino_millis",
    "sensor_read_ms",
    "total_isr_ms",
    "dropped",
    "tail_fill",
    "overheat_occurred",
    "overheat_frame",
    "overheat_coil",
    "coil_currents",
    "coil_temperatures",
    "field_values",
  ]
  writedlm(protocol.streamCsvHandle, [header], ',')
  flush(protocol.streamCsvHandle)  # ensure header is written immediately
  return csvPath
end

function serializeCoilCurrents(currents)
  isempty(currents) && return ""
  parts = String[]
  for (name, value) in sort(collect(currents); by = x -> coilChannelSortKey(x[1]))
    push!(parts, "$(name)=$(value)")
  end
  return join(parts, ";")
end

function serializeCoilTemperatures(temperatures)
  isempty(temperatures) && return ""
  return join(string.(temperatures), ";")
end

function serializeFieldValues(data)
  values = ustrip.(u"T", vec(data))
  return join(string.(Float64.(values)), ";")
end

function appendFrameToStreamingCsv!(protocol::PorridgeFieldMeasurementProtocol,
                                     result::FieldCameraResult,
                                     frameIndex::Int;
                                     patchIdx::Int,
                                     coilCurrentsSerialized::String,
                                     coilTemperaturesSerialized::String="",
                                     dropped::Bool=false,
                                     tailFill::Bool=false,
                                     overheatOccurred::Bool=protocol.overheatOccurred,
                                     overheatFrame::Int64=protocol.overheatFrame,
                                     overheatCoil::Int64=protocol.overheatCoilID)
  if isnothing(protocol.streamCsvHandle)
    prepareStreamingCsv!(protocol; requestedOutputPath=protocol.requestedOutputPath)
  end
  if isnothing(protocol.streamCsvHandle)
    return
  end

  row = Any[
    frameIndex,
    patchIdx,
    result.reading_id,
    result.timestamp,
    result.arduino_millis,
    result.sensor_read_ms,
    result.total_isr_ms,
    dropped,
    tailFill,
    overheatOccurred,
    overheatFrame,
    overheatCoil,
    coilCurrentsSerialized,
    coilTemperaturesSerialized,
    serializeFieldValues(result.data),
  ]
  writedlm(protocol.streamCsvHandle, [row], ',')
  flush(protocol.streamCsvHandle)  # flush line-by-line to reduce memory pressure
end

function timeEstimate(protocol::PorridgeFieldMeasurementProtocol)
  isnothing(protocol.params.sequence) && return "Unknown"
  # ~100 ms per triggered frame is a reasonable estimate
  return string(acqNumFrames(protocol.params.sequence) * 0.1 * 1u"s")
end