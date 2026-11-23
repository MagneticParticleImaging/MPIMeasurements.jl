# Datagram from LiveFieldFeed.jl (measurement process) to LiveFieldViewer.jl (viewer process).
# Included by both, so the two sides always agree on the layout. Base Julia only.
#
# One UDP datagram per feed period, little-endian:
#   "MSLF"                    4 bytes
#   version                   UInt16
#   n                         UInt16   sensors in this datagram, 0 = no frame yet
#   frameCount                Int64    trigger index of this frame in the run (same value = same frame)
#   timestamp                 UInt64   sphere clock of the frame, µs
#   sentAt                    Float64  time() on the measurement PC
#   positions                 3n Float32, sensor positions in m (column s = sensor s)
#   field                     3n Float32, field in T, NaN for invalid sensors
#   statusLength, status      UInt16 + UTF-8, one line from the measurement script

const LIVE_FIELD_MAGIC = codeunits("MSLF")
const LIVE_FIELD_VERSION = UInt16(1)
const LIVE_FIELD_DEFAULT_PORT = 52525
const LIVE_FIELD_MAX_STATUS_CHARS = 300

struct LiveFieldPacket
  frameCount::Int64
  timestamp::UInt64
  sentAt::Float64
  positions::Matrix{Float32}   # 3×n, m
  field::Matrix{Float32}       # 3×n, T
  status::String
end

function encodeLiveFieldPacket(p::LiveFieldPacket)
  n = size(p.field, 2)
  size(p.positions) == (3, n) && size(p.field, 1) == 3 ||
    throw(DimensionMismatch("positions and field must both be 3×n"))
  status = Vector{UInt8}(first(p.status, LIVE_FIELD_MAX_STATUS_CHARS))
  io = IOBuffer(sizehint = 4 + 2 + 2 + 3 * 8 + 2 * 12n + 2 + length(status))
  write(io, LIVE_FIELD_MAGIC)
  write(io, htol(LIVE_FIELD_VERSION), htol(UInt16(n)))
  write(io, htol(p.frameCount), htol(p.timestamp), htol(p.sentAt))
  for v in p.positions
    write(io, htol(v))
  end
  for v in p.field
    write(io, htol(v))
  end
  write(io, htol(UInt16(length(status))), status)
  return take!(io)
end

"Parse a datagram; `nothing` if it is not a LiveFieldPacket of this version."
function decodeLiveFieldPacket(bytes::AbstractVector{UInt8})
  length(bytes) >= 34 && bytes[1:4] == LIVE_FIELD_MAGIC || return nothing
  io = IOBuffer(bytes)
  skip(io, 4)
  ltoh(read(io, UInt16)) == LIVE_FIELD_VERSION || return nothing
  n = Int(ltoh(read(io, UInt16)))
  length(bytes) >= 34 + 24n + 2 || return nothing
  frameCount = ltoh(read(io, Int64))
  timestamp = ltoh(read(io, UInt64))
  sentAt = ltoh(read(io, Float64))
  positions = Matrix{Float32}(undef, 3, n)
  field = Matrix{Float32}(undef, 3, n)
  for i in eachindex(positions)
    positions[i] = ltoh(read(io, Float32))
  end
  for i in eachindex(field)
    field[i] = ltoh(read(io, Float32))
  end
  statusLength = Int(ltoh(read(io, UInt16)))
  bytesavailable(io) >= statusLength || return nothing
  status = String(read(io, statusLength))
  return LiveFieldPacket(frameCount, timestamp, sentAt, positions, field, status)
end
