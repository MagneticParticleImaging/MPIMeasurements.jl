using Dates
using Statistics
using LibSerialPort
using Printf

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
    sof1Hits::Int = 0
    sofPairs::Int = 0
    duplicateIds::Int = 0
    missingIds::Int = 0
    havePrev::Bool = false
    prevId::Int = -1
    asciiBytes::Int = 0
    nonAsciiBytes::Int = 0
    maxBufferBytes::Int = 0
    asciiDigitLines::Int = 0
    asciiLinesTotal::Int = 0
end

function count_numeric_ascii_lines(bytes::Vector{UInt8})
    isempty(bytes) && return 0, 0
    s = String(Char.(bytes))
    lines = split(replace(s, "\r" => ""), '\n')
    total = 0
    numeric = 0
    for line in lines
        t = strip(line)
        isempty(t) && continue
        total += 1
        all(isdigit, t) && (numeric += 1)
    end
    return numeric, total
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

    stats.maxBufferBytes = max(stats.maxBufferBytes, buflen)

    while idx + 1 <= buflen
        if buffer[idx] == SOF1
            stats.sof1Hits += 1
            if buffer[idx + 1] == SOF2
                stats.sofPairs += 1
            end
        end

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
    println("ASCII bytes:          ", stats.asciiBytes)
    println("Non-ASCII bytes:      ", stats.nonAsciiBytes)
    println("Numeric ASCII lines:  ", stats.asciiDigitLines, "/", stats.asciiLinesTotal)
    println("SOF 0xA5 hits:        ", stats.sof1Hits)
    println("SOF pair A5 5A hits:  ", stats.sofPairs)
    println("Valid frames:         ", stats.validFrames)
    println("Marker skips:         ", stats.markerSkips)
    println("Checksum failures:    ", stats.checksumFailures)
    println("Duplicate reading_id: ", stats.duplicateIds)
    println("Missing reading_id:   ", stats.missingIds)
    println("Max parser buffer:    ", stats.maxBufferBytes, " bytes")

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

    println("\n=== Stream Classification ===")
    if stats.bytesRead == 0
        println("No stream: received zero bytes. Check COM port selection, device reset state, and diagnostic mode.")
    elseif stats.sofPairs == 0
        numericRatio = stats.asciiLinesTotal > 0 ? stats.asciiDigitLines / stats.asciiLinesTotal : 0.0
        if stats.asciiBytes > stats.nonAsciiBytes
            if numericRatio > 0.8 && stats.asciiLinesTotal >= 5
                println("Numeric ASCII line stream detected (e.g., debug println values). This is not the framed packet stream.")
                println("Likely causes: wrong firmware flashed, wrong diagnostic mode, wrong serial port, or active debug prints.")
            else
                println("ASCII-like stream without framed packets. You are likely reading text output, not binary framed packets.")
            end
        else
            println("Binary/noisy stream without SOF pairs. Likely wrong baud/port/firmware mode or severe corruption.")
        end
    elseif stats.validFrames == 0 && stats.checksumFailures > 0
        println("Framed markers found but checksum always failing. Transport corruption is occurring before host parsing.")
    elseif stats.validFrames > 0 && stats.missingIds == 0 && stats.checksumFailures == 0
        println("Healthy framed stream for this interval.")
    else
        println("Framed stream present with losses/corruption. Use mode comparison (1 vs 2 vs 0) to localize stage.")
    end

    println("\n=== Interpretation Hints ===")
    println("1) Mode 1 (synthetic stream-only) should have near-zero checksum failures and missing IDs.")
    println("2) If Mode 1 fails: USB TX path / cable / host serial reader is the bottleneck.")
    println("3) If Mode 1 passes but Mode 2 fails: trigger detection/timing path is the bottleneck.")
    println("4) If Modes 1+2 pass but Mode 0 fails: sensor read/SPI path is the bottleneck.")
end

function preview_bytes(bytes::Vector{UInt8}, n::Int)
    k = min(n, length(bytes))
    k == 0 && return
    head = bytes[1:k]
    hexLine = join((@sprintf("%02X", b) for b in head), " ")
    asciiLine = String(map(b -> (b >= 32 && b <= 126) ? Char(b) : '.', head))
    println("\nFirst ", k, " bytes (hex):   ", hexLine)
    println("First ", k, " bytes (ascii): ", asciiLine)
end

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. example/SerialByteLossDiagnostics.jl <PORT> [BAUD=250000] [DURATION_S=30] [EXPECTED_HZ] [PREVIEW_BYTES=64]")
        println("Example: julia --project=. example/SerialByteLossDiagnostics.jl COM7 250000 30 50 64")
        return
    end

    port = ARGS[1]
    baud = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 250000
    durationS = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : 30.0
    expectedHz = length(ARGS) >= 4 ? parse(Float64, ARGS[4]) : nothing
    previewN = length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 64

    println("Opening ", port, " at ", baud, " baud")
    sp = SerialPort(port)
    open(sp)
    set_speed(sp, baud)
    set_frame(sp, ndatabits=8, parity=SP_PARITY_NONE, nstopbits=1)
    sp_flush(sp, SP_BUF_BOTH)

    stats = DiagStats()
    frameTimes = Float64[]
    buffer = UInt8[]
    allBytes = UInt8[]

    tStart = time()
    deadline = tStart + durationS

    try
        while time() < deadline
            nbytes, chunk = LibSerialPort.sp_blocking_read(sp.ref, 8192, 100)
            if nbytes > 0
                append!(buffer, @view chunk[1:nbytes])
                append!(allBytes, @view chunk[1:nbytes])
                stats.bytesRead += nbytes
                for b in @view chunk[1:nbytes]
                    if (b == 9) || (b == 10) || (b == 13) || (b >= 32 && b <= 126)
                        stats.asciiBytes += 1
                    else
                        stats.nonAsciiBytes += 1
                    end
                end
                buffer = parse_frames(buffer, stats, frameTimes)
            end
        end
    finally
        close(sp)
    end

    stats.asciiDigitLines, stats.asciiLinesTotal = count_numeric_ascii_lines(allBytes)

    preview_bytes(allBytes, previewN)
    print_summary(stats, frameTimes, time() - tStart, expectedHz)
end

main()
