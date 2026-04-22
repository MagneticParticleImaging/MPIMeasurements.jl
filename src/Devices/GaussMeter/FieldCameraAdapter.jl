using LinearAlgebra

export FieldCameraAdapter, FieldCameraAdapterParams, FieldCameraResult

abstract type FieldCameraAdapterParams <: DeviceParams end

Base.@kwdef struct FieldCameraAdapterDirectParams <: FieldCameraAdapterParams
  portAddress::String = "/dev/ttyACM0"
  measurementRange::Int64 = 150
  numSensors::Int64 = 37
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I, (3, 3))
  @add_serial_device_fields "\r" 8 SP_PARITY_NONE
end

FieldCameraAdapterDirectParams(dict::Dict) = params_from_dict(FieldCameraAdapterDirectParams, dict)

struct FieldCameraResult
  timestamp::Float64
  data::Matrix{typeof(1.0u"T")}  # 3 × numSensors
  reading_id::Int                 # Arduino trigger counter, -1 if unavailable
  arduino_millis::Int             # millis() from Arduino, -1 if unavailable
  sensor_read_ms::Int             # sensor read time reported by Arduino, -1 if unavailable
  total_isr_ms::Int               # total ISR time reported by Arduino, -1 if unavailable
end

FieldCameraResult(timestamp::Float64, data::Matrix{typeof(1.0u"T")}) =
  FieldCameraResult(timestamp, data, -1, -1, -1, -1)

Base.@kwdef mutable struct FieldCameraAdapter <: GaussMeter
  @add_device_fields FieldCameraAdapterParams
  sd::Union{SerialDevice, Nothing} = nothing
  lock::ReentrantLock = ReentrantLock()
  lastReading::Int = -1
  rawBuffer::Vector{UInt8} = UInt8[]
  pendingResults::Vector{FieldCameraResult} = FieldCameraResult[]
end

neededDependencies(::FieldCameraAdapter) = []
optionalDependencies(::FieldCameraAdapter) = [SerialPortPool]

const FC_SENSORS = [
  2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
  22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
  35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 34
]

const FC_TDESIGN_REORDER = [
  34, 19, 17, 29, 25, 33,  4, 11, 12, 14, 32,  7,
   1,  8, 13, 16,  6,  9, 24, 36, 22, 27, 23, 10,
  21, 30, 35,  3, 15, 31, 20, 18, 28,  2,  5, 26
]

const FC_BOTTOM = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 43, 44, 45, 46]
const FC_BOTTOM_IDX = [findfirst(==(s), FC_SENSORS) for s in FC_BOTTOM]

const FC_POS_X = [
  23.17546, 1.64737, -1.64737, 11.3194, -10.5912, 9.01035, -18.77659, -9.01053, -27.39906,
  -23.17546, -29.80074, -11.3294, -23.17546, -29.80074, -35.41345, -27.39906, -18.77659, 1.64737,
  -11.3294, -35.41345, -10.5912, -9.01053, 23.17546, 9.01053, 11.3294, 10.5912, 27.39906,
  35.41345, 29.80074, 35.41345, -1.64737, 18.77659, 29.80074, 18.77659, 10.5912, 27.39906, 0.0
]
const FC_POS_Y = [
  -9.01053, -10.5912, -10.5912, -29.80074, -35.41345, -27.39906, -11.3294, -27.39906, -23.17546,
  -9.01053, -18.77659, -29.80074, 9.01053, 18.77659, -1.64737, 23.17546, 11.3294, 10.5912,
  29.80074, 1.64737, 35.41345, 27.39906, 9.01053, 27.39906, 29.80074, 35.41345, 23.17546,
  1.64737, 18.77659, -1.64737, 10.5912, 11.3294, -18.77659, -11.3294, -35.41345, -23.17546, 0.0
]
const FC_POS_Z = [
  -27.39906, -35.41345, 35.41345, 18.77659, 1.64737, -23.17546, -29.80074, 23.17546, 9.01053,
  27.39906, -11.3294, -18.77659, -27.39906, 11.3294, 10.5912, -9.01053, 29.80074, 35.41345,
  18.77659, -10.5912, -1.64737, -23.17546, 27.39906, 23.17546, -18.77659, 1.64737, 9.01053,
  10.5912, -11.3294, -10.5912, -35.41345, -29.80074, 11.3294, 29.80074, -1.64737, -9.01053, 0.0
]

const FC_OFFSETS = Dict{Int, NamedTuple{(:x,:y,:z), Tuple{Vector{Float64},Vector{Float64},Vector{Float64}}}}(
  300 => (
    x = [-0.14, -0.27, -0.11, -0.41, -0.18, -0.38, -0.26, -0.28, -0.27, -0.47,
         -0.23, -0.32, -0.37, -0.65, -0.44, -0.27, -0.50, -0.48, -0.19, -0.42,
         -0.36, -0.27, -0.29, -0.50, -0.45, -0.28, -0.13, -0.27, -0.42, -0.55,
         -0.46, -0.33, -0.25, -0.11, -0.02, -0.20, -0.29],
    y = [-0.28, -0.26, -0.51, -0.41, -0.24, -0.25, -0.40, -0.04,  0.09, -0.42,
         -0.47, -0.29, -0.29, -0.31, -0.52, -0.32, -0.40, -0.39, -0.56, -0.22,
         -0.34, -0.18, -0.58, -0.33, -0.52, -0.19, -0.14, -0.48, -0.36, -0.55,
         -0.41, -0.31, -0.28, -0.24, -0.30,  0.08, -0.45],
    z = [-0.52, -0.38, -0.33, -0.41, -0.38, -0.45, -0.27, -0.42, -0.19, -0.35,
         -0.25, -0.30, -0.30, -0.42, -0.29, -0.32, -0.31, -0.53, -0.68, -0.42,
         -0.42, -0.43, -0.39, -0.47, -0.50, -0.41, -0.24, -0.39, -0.47, -0.50,
         -0.35, -0.41, -0.30, -0.21, -0.31, -0.14, -0.33],
  ),
  150 => (
    x = [ 0.24,  0.06,  0.20,  0.03,  0.05,  0.00,  0.03,  0.04, -0.08,  0.03,
          0.12,  0.08, -0.14, -0.20,  0.07,  0.10, -0.12, -0.02,  0.03, -0.08,
          0.02,  0.04,  0.16,  0.00,  0.04,  0.05, -0.01,  0.16,  0.04,  0.00,
         -0.03, -0.03,  0.10,  0.06,  0.22, -0.03,  0.03],
    y = [ 0.06,  0.14, -0.18,  0.06,  0.06,  0.13,  0.02,  0.21,  0.34, -0.09,
         -0.01,  0.04,  0.02,  0.07,  0.03,  0.03,  0.02,  0.14,  0.07,  0.08,
          0.01,  0.12, -0.17,  0.09,  0.00,  0.11,  0.02, -0.11,  0.08, -0.03,
         -0.01, -0.01,  0.10,  0.07,  0.01,  0.16, -0.14],
    z = [-0.21,  0.01,  0.02, -0.03, -0.01, -0.06,  0.02, -0.11, -0.03,  0.10,
          0.02,  0.02, -0.01,  0.01,  0.01,  0.02,  0.04, -0.04, -0.08, -0.09,
         -0.02, -0.11, -0.01, -0.01, -0.04, -0.09, -0.07, -0.22, -0.06, -0.03,
         -0.01, -0.11,  0.02, -0.05,  0.02, -0.01, -0.02],
  ),
  75 => (
    x = [ 0.25,  0.11,  0.27,  0.04,  0.09,  0.01,  0.06,  0.05, -0.04,  0.09,
          0.15,  0.12, -0.14, -0.16,  0.01,  0.12, -0.08,  0.00,  0.05, -0.04,
          0.06,  0.09,  0.23,  0.05,  0.04,  0.08,  0.02,  0.21,  0.08,  0.05,
          0.05,  0.01,  0.15,  0.07,  0.24,  0.01,  0.06],
    y = [ 0.14,  0.18, -0.13,  0.07,  0.12,  0.13,  0.05,  0.23,  0.37, -0.05,
          0.03,  0.08,  0.03,  0.11, -0.02,  0.06,  0.05,  0.16,  0.10,  0.10,
          0.04,  0.16, -0.15,  0.14,  0.06,  0.15,  0.07, -0.10,  0.12, -0.02,
          0.01,  0.02,  0.13,  0.09,  0.05,  0.20, -0.11],
    z = [-0.16,  0.05,  0.06,  0.00,  0.05, -0.03,  0.05, -0.08,  0.00,  0.15,
          0.05,  0.05,  0.01,  0.05,  0.06,  0.04,  0.07, -0.01, -0.05, -0.07,
          0.01, -0.08,  0.03,  0.03, -0.01, -0.07, -0.05,  0.02, -0.03,  0.01,
          0.03, -0.07,  0.06, -0.03,  0.04,  0.03,  0.02],
  ),
)

const FC_ERRORS = Set(["F$i" for i in 2:28])

"Parse sensor readings in `*x<y>z#` format into 3×N matrix."
function parseSensorBlock(data::String, numSensors::Int)
  stars = findall("*", data)
  hashes = findall("#", data)
  n = min(length(stars), length(hashes), numSensors)
  values = zeros(3, numSensors)
  for i in 1:n
    try
      segment = SubString(data, stars[i][1]+1, hashes[i][1]-1)
      lt = findfirst('<', segment)
      gt = findfirst('>', segment)
      (isnothing(lt) || isnothing(gt)) && continue
      values[1, i] = parse(Float64, segment[1:lt-1])
      values[2, i] = parse(Float64, segment[lt+1:gt-1])
      values[3, i] = parse(Float64, segment[gt+1:end])
    catch
      continue
    end
  end
  return values
end

"Apply calibration offsets for the given measurement range."
function applyOffsets!(values::Matrix{Float64}, range::Int)
  off = get(FC_OFFSETS, range, nothing)
  isnothing(off) && error("Invalid measurement range: $range mT")
  values[1, :] .-= off.x
  values[2, :] .-= off.y
  values[3, :] .-= off.z
  return values
end

function invertBottom!(values::Matrix{Float64})
  for idx in FC_BOTTOM_IDX
    values[1, idx] *= -1
    values[3, idx] *= -1
  end
  return values
end

"Return 3×37 sensor positions matrix in mm."
function getSensorPositions()
  return Matrix{Float64}(hcat(FC_POS_X, FC_POS_Y, FC_POS_Z)')
end

function _init(cam::FieldCameraAdapter)
  params = cam.params
  cam.sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  @info "FieldCameraAdapter connected at $(params.portAddress)"
end

"On-demand full-frame acquisition via ALLSENSORSARDUINO command."
function acquireFullField(cam::FieldCameraAdapter)
  lock(cam.lock) do
    rangeHex = cam.params.measurementRange == 75 ? "1" :
               cam.params.measurementRange == 150 ? "0" : "2"
    cmd = "\"*ALLSENSORSARDUINO?>0x$(rangeHex)|0x0#\""
    data = query(cam.sd, cmd)
    data in FC_ERRORS && error("ALLSENSORSARDUINO error: $data")

    values = parseSensorBlock(data, cam.params.numSensors)
    applyOffsets!(values, cam.params.measurementRange)
    invertBottom!(values)

    return FieldCameraResult(time(), values .* 1u"mT")
  end
end

getXValue(cam::FieldCameraAdapter)    = mean(acquireFullField(cam).data[1, :])
getYValue(cam::FieldCameraAdapter)    = mean(acquireFullField(cam).data[2, :])
getZValue(cam::FieldCameraAdapter)    = mean(acquireFullField(cam).data[3, :])
getTemperature(::FieldCameraAdapter)  = 0.0u"°C"
getFrequency(::FieldCameraAdapter)    = 0.0u"Hz"
calculateFieldError(::FieldCameraAdapter, ::Vector{<:Unitful.BField}) = 0.0u"T"

function getXYZValues(cam::FieldCameraAdapter)
  r = acquireFullField(cam)
  return [mean(r.data[1, :]), mean(r.data[2, :]), mean(r.data[3, :])]
end

function Base.close(cam::FieldCameraAdapter)
  if !isnothing(cam.sd)
    close(cam.sd)
    cam.sd = nothing
  end
  @info "FieldCameraAdapter closed"
end

function enable(cam::FieldCameraAdapter)
  cam.lastReading = -1
  empty!(cam.rawBuffer)
  empty!(cam.pendingResults)
  isnothing(cam.sd) && return
  lock(cam.lock) do
    while true
      nbytes, _ = LibSerialPort.sp_blocking_read(cam.sd.sp.ref, 4096, 100)
      nbytes == 0 && break
    end
  end

  # Async reading of triggered fields
end

function disable(cam::FieldCameraAdapter)
  nothing
end

function _readRawTriggeredBytes!(cam::FieldCameraAdapter; timeout_ms::Int=10, maxReads::Int=1)
  isnothing(cam.sd) && return 0
  bytesRead = 0
  for _ in 1:maxReads
    nbytes, chunk = LibSerialPort.sp_blocking_read(cam.sd.sp.ref, 8192, timeout_ms)
    nbytes == 0 && break
    append!(cam.rawBuffer, @view chunk[1:nbytes])
    bytesRead += nbytes
  end
  return bytesRead
end

@inline function _wordHasExpectedHeader(word::UInt64)
  ((word >> 48) & 0xFFFF) == 0x0000
end

@inline function _unpackSigned16(word::UInt64, shift::Int)
  return reinterpret(Int16, UInt16((word >> shift) & 0xFFFF))
end

@inline function _xorChecksum(buffer::Vector{UInt8}, startIdx::Int, endIdx::Int)
  checksum = UInt8(0)
  for idx in startIdx:endIdx
    checksum = xor(checksum, buffer[idx])
  end
  return checksum
end

function _parseTriggeredFrames!(cam::FieldCameraAdapter)
  numSensors = cam.params.numSensors
  legacyFrameBytes = 8 * numSensors + 1
  framedFrameBytes = 2 + legacyFrameBytes + 1
  length(cam.rawBuffer) < legacyFrameBytes && return 0

  scale = cam.params.measurementRange / 2.0^15
  parsed = 0
  droppedPrefixBytes = 0
  idx = 1
  buflen = length(cam.rawBuffer)

  while idx + legacyFrameBytes - 1 <= buflen
    useFramed = idx + framedFrameBytes - 1 <= buflen &&
                cam.rawBuffer[idx] == 0xA5 && cam.rawBuffer[idx + 1] == 0x5A

    payloadStart = useFramed ? idx + 2 : idx
    readingPos = payloadStart + 8 * numSensors
    checksumPos = readingPos + 1

    if useFramed
      expectedChecksum = _xorChecksum(cam.rawBuffer, payloadStart, readingPos)
      if expectedChecksum != cam.rawBuffer[checksumPos]
        idx += 1
        droppedPrefixBytes += 1
        continue
      end
    end

    aligned = true
    for sensorIdx in 0:(numSensors - 1)
      startByte = payloadStart + sensorIdx * 8
      packed = reinterpret(UInt64, cam.rawBuffer[startByte:startByte+7])[1]
      if !_wordHasExpectedHeader(packed)
        aligned = false
        break
      end
    end

    if !aligned
      idx += 1
      droppedPrefixBytes += 1
      continue
    end

    reading = Int(cam.rawBuffer[readingPos])
    if reading == cam.lastReading
      idx += useFramed ? framedFrameBytes : legacyFrameBytes
      continue
    end

    values = zeros(3, numSensors)
    for sensorIdx in 0:(numSensors - 1)
      startByte = payloadStart + sensorIdx * 8
      packed = reinterpret(UInt64, cam.rawBuffer[startByte:startByte+7])[1]
      values[1, sensorIdx + 1] = _unpackSigned16(packed, 0) * scale
      values[2, sensorIdx + 1] = _unpackSigned16(packed, 16) * scale
      values[3, sensorIdx + 1] = _unpackSigned16(packed, 32) * scale
    end

    applyOffsets!(values, cam.params.measurementRange)
    invertBottom!(values)

    cam.lastReading = reading
    push!(cam.pendingResults, FieldCameraResult(time(), values .* 1u"mT", reading, 0, 0, 0))

    parsed += 1
    idx += useFramed ? framedFrameBytes : legacyFrameBytes
  end

  if idx > 1
    cam.rawBuffer = cam.rawBuffer[idx:end]
  end

  if droppedPrefixBytes > 0
    @warn "Resynchronized field-camera stream" dropped_bytes=droppedPrefixBytes remaining_buffer=length(cam.rawBuffer)
  end

  return parsed
end

"Poll serial stream, parse all complete triggered frames and return newly parsed results."
function pollTriggeredFields(cam::FieldCameraAdapter; timeout_ms::Int=10, maxReads::Int=1)
  lock(cam.lock) do
    _readRawTriggeredBytes!(cam; timeout_ms, maxReads)
    _parseTriggeredFrames!(cam)

    if isempty(cam.pendingResults)
      return FieldCameraResult[]
    end

    out = copy(cam.pendingResults)
    empty!(cam.pendingResults)
    return out
  end
end

"Read all buffered serial data and parse every complete measurement block."
function readAllTriggeredFields(cam::FieldCameraAdapter; timeout_ms::Int=500)
  results = FieldCameraResult[]
  while true
    batch = pollTriggeredFields(cam; timeout_ms, maxReads=1)
    isempty(batch) && break
    append!(results, batch)
  end
  return results
end
