using Dates
using Statistics
using LibSerialPort

const SOF1 = UInt8(0xA5)
const SOF2 = UInt8(0x5A)
const NUM_SENSORS = 37
const PAYLOAD_BYTES = 8 * NUM_SENSORS
const FRAME_BYTES = 2 + PAYLOAD_BYTES + 1 + 1

Base.@kwdef mutable struct DiagStats
    bytesRead::Int = 0
    validFrames::Int = 0
    checksumFailures::Int = 0
    markerSkips::Int = 0
    duplicateIds::Int = 0
    missingIds::Int = 0
    havePrev::Bool = false
    prevId::Int = -1
end

@inline function xor_checksum(buffer::Vector{UInt8}, startIdx::Int, endIdx::Int)
    checksum = UInt8(0)
    for i in startIdx:endIdx
        checksum = xor(checksum, buffer[i])
    end
    return checksum
end

function parse_frames(buffer::Vector{UInt8}, stats::DiagStats, frameTimes::Vector{Float64})
    idx = 1
    buflen = length(buffer)

    while idx + 1 <= buflen
        if !(buffer[idx] == SOF1 && buffer[idx + 1] == SOF2)
            idx += 1
            stats.markerSkips += 1
            continue
        end

        if idx + FRAME_BYTES - 1 > buflen
            break
        end

        payloadStart = idx + 2
        readingPos = payloadStart + PAYLOAD_BYTES
        checksumPos = readingPos + 1

        expectedChecksum = xor_checksum(buffer, payloadStart, readingPos)
        if expectedChecksum != buffer[checksumPos]
            stats.checksumFailures += 1
            idx += 1
            continue
        end

        readingId = Int(buffer[readingPos])
        if stats.havePrev
            delta = mod(readingId - stats.prevId, 256)
            if delta == 0
                stats.duplicateIds += 1
            elseif delta == 1
                nothing
            else
                stats.missingIds += delta - 1
            end
        end

        stats.prevId = readingId
        stats.havePrev = true
        stats.validFrames += 1
        push!(frameTimes, time())

        idx += FRAME_BYTES
    end

    if idx <= buflen
        return copy(@view buffer[idx:buflen])
    end

    return UInt8[]
end

function print_summary(stats::DiagStats, frameTimes::Vector{Float64}, durationS::Float64, expectedHz::Union{Nothing,Float64})
    println("\n=== Serial Diagnostic Summary ===")
    println("Bytes read:           ", stats.bytesRead)
    println("Valid frames:         ", stats.validFrames)
    println("Marker skips:         ", stats.markerSkips)
    println("Checksum failures:    ", stats.checksumFailures)
    println("Duplicate reading_id: ", stats.duplicateIds)
    println("Missing reading_id:   ", stats.missingIds)

    obsHz = stats.validFrames / max(durationS, eps())
    println("Observed frame rate:  ", round(obsHz, digits=2), " Hz")

    if length(frameTimes) > 1
        dt = diff(frameTimes)
        println("Inter-frame dt mean:  ", round(mean(dt) * 1000, digits=2), " ms")
        println("Inter-frame dt std:   ", round(std(dt) * 1000, digits=2), " ms")
    end

    if !isnothing(expectedHz)
        expectedFrames = Int(round(expectedHz * durationS))
        missingVsExpected = max(expectedFrames - stats.validFrames, 0)
        println("Expected frames:      ", expectedFrames)
        println("Frames shortfall:     ", missingVsExpected)
    end

    println("\n=== Interpretation Hints ===")
    println("1) Mode 1 (synthetic stream-only) should have near-zero checksum failures and missing IDs.")
    println("2) If Mode 1 fails: USB TX path / cable / host serial reader is the bottleneck.")
    println("3) If Mode 1 passes but Mode 2 fails: trigger detection/timing path is the bottleneck.")
    println("4) If Modes 1+2 pass but Mode 0 fails: sensor read/SPI path is the bottleneck.")
end

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. example/SerialByteLossDiagnostics.jl <PORT> [BAUD=250000] [DURATION_S=30] [EXPECTED_HZ]")
        println("Example: julia --project=. example/SerialByteLossDiagnostics.jl COM7 250000 30 50")
        return
    end

    port = ARGS[1]
    baud = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 250000
    durationS = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : 30.0
    expectedHz = length(ARGS) >= 4 ? parse(Float64, ARGS[4]) : nothing

    println("Opening ", port, " at ", baud, " baud")
    sp = SerialPort(port)
    open(sp)
    set_speed(sp, baud)
    set_frame(sp, ndatabits=8, parity=SP_PARITY_NONE, nstopbits=1)
    sp_flush(sp, SP_BUF_BOTH)

    stats = DiagStats()
    frameTimes = Float64[]
    buffer = UInt8[]

    tStart = time()
    deadline = tStart + durationS

    try
        while time() < deadline
            nbytes, chunk = LibSerialPort.sp_blocking_read(sp.ref, 8192, 100)
            if nbytes > 0
                append!(buffer, @view chunk[1:nbytes])
                stats.bytesRead += nbytes
                buffer = parse_frames(buffer, stats, frameTimes)
            end
        end
    finally
        close(sp)
    end

    print_summary(stats, frameTimes, time() - tStart, expectedHz)
end

main()
