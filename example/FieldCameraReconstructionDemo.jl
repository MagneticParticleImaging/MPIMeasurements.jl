using MPIMeasurements
using SphericalHarmonicExpansions
using TypedPolynomials
using LinearAlgebra
using Printf
using Plots
using Unitful

default(
    legend = false,
    dpi = 150,
    size = (1250, 420),
    background_color = :white,
    foreground_color = :black,
    guidefont = font(10),
    tickfont = font(8),
    titlefont = font(10),
)

const TEST_MODE      = true
const SCANNER_NAME   = "PorridgeFieldCamera"
const RADIUS_MM      = 37.0
const R              = RADIUS_MM / 1000
const T_DESIGN       = 8
const L              = T_DESIGN ÷ 2
const GRID_N         = 81
const UPDATE_SECONDS = 0.25
const COLOR_LIM_MT   = (0.0, 2.5)

const REORDER          = MPIMeasurements.FC_TDESIGN_REORDER
const SENSOR_POS       = MPIMeasurements.getSensorPositions()[:, REORDER]
const N                = size(SENSOR_POS, 2)
const DIRS             = SENSOR_POS ./ sqrt.(sum(abs2, SENSOR_POS; dims = 1))
const FIELD_CORRECTION = [-1.0 0.0 0.0; 0.0 0.0 1.0; 0.0 -1.0 0.0]

TypedPolynomials.@polyvar x y z
const TERMS  = [(l, m) for l in 0:L for m in -l:l]
const ZPOLY  = [SphericalHarmonicExpansions.zlm(l, m, x, y, z) for (l, m) in TERMS]
const WEIGHT = [(2l + 1) / (R^l * N) for (l, _) in TERMS]

evalZ(p, q) = try Float64(p(x => q[1], y => q[2], z => q[3])) catch; Float64(p) end

# Basis at the unit sensor directions, fixed across frames.
const PSI = [evalZ(ZPOLY[j], DIRS[:, k]) for k in 1:N, j in eachindex(TERMS)]

# t-design quadrature: coefficients γ[component, term] for one field frame.
coeffs(field) = (field * PSI) .* reshape(WEIGHT, 1, :)

const COORDS    = collect(range(-R, R; length = GRID_N))
const COORDS_MM = COORDS .* 1000

function planeBasis(plane)
    pts    = NTuple{3,Float64}[]
    inside = Bool[]
    for b in COORDS, a in COORDS
        q = plane === :xy ? (a, b, 0.0) : plane === :xz ? (a, 0.0, b) : (0.0, a, b)
        push!(pts, q)
        push!(inside, q[1]^2 + q[2]^2 + q[3]^2 <= R^2)
    end
    Φ = [evalZ(ZPOLY[j], p) for p in pts, j in eachindex(TERMS)]
    return Φ, inside
end

const PLANES = Dict(p => planeBasis(p) for p in (:xy, :xz, :yz))

function sliceMagnitude(γ, plane)
    Φ, inside = PLANES[plane]
    mag = sqrt.((Φ * γ[1, :]) .^ 2 .+ (Φ * γ[2, :]) .^ 2 .+ (Φ * γ[3, :]) .^ 2) .* 1000
    mag[.!inside] .= NaN
    return reshape(mag, GRID_N, GRID_N)
end

function syntheticField(frame)
    t = frame * UPDATE_SECONDS
    drift = [0.7sin(0.8t), 0.6cos(0.7t), 0.5sin(0.5t)] .* 1e-3
    field = zeros(3, N)
    for k in 1:N
        r = DIRS[:, k] .* R
        field[1, k] = drift[1] + 0.8r[1] - 0.3r[2] + 0.2r[3]
        field[2, k] = drift[2] - 0.2r[1] + 0.7r[2] + 0.1r[3]
        field[3, k] = drift[3] + 0.1r[1] + 0.3r[2] - 0.9r[3]
    end
    return field
end

function acquire(cam, frame)
    TEST_MODE && return syntheticField(frame)
    try
        raw = ustrip.(u"T", MPIMeasurements.acquireFullField(cam).data[:, REORDER])
        return FIELD_CORRECTION * raw
    catch err
        err isa InterruptException && rethrow()
        @warn "Field read failed, skipping frame" exception = err
        return nothing
    end
end

function renderFrame(γ, frame)
    ticks = [-RADIUS_MM, 0, RADIUS_MM]
    panel(plane, xl, yl, title) = begin
        p = heatmap(COORDS_MM, COORDS_MM, sliceMagnitude(γ, plane);
            c = :viridis, clim = COLOR_LIM_MT, aspect_ratio = :equal,
            xlabel = xl, ylabel = yl, title = title,
            xticks = ticks, yticks = ticks, colorbar = false)
        hline!(p, [0.0]; color = :white, alpha = 0.35, linewidth = 1)
        vline!(p, [0.0]; color = :white, alpha = 0.35, linewidth = 1)
        p
    end

    p1 = panel(:xy, "x / mm", "y / mm", @sprintf("xy slice (z = 0)  ·  frame %d", frame))
    p2 = panel(:xz, "x / mm", "z / mm", "xz slice (y = 0)")
    p3 = panel(:yz, "y / mm", "z / mm", "yz slice (x = 0)")
    pbar = heatmap([0.0 1.0; 0.0 1.0];
        c = :viridis, clim = COLOR_LIM_MT, colorbar = true,
        colorbar_title = "|B| / mT", showaxis = false, framestyle = :none,
        xticks = false, yticks = false, grid = false)

    return plot(p1, p2, p3, pbar, layout = @layout([a b c d{0.12w}]), size = (1700, 420))
end

function openLiveCamera()
    scanner = MPIScanner(SCANNER_NAME; robust = true)
    init(scanner)
    return scanner, getGaussMeter(scanner)
end

function run_demo(; maxFrames = Inf)
    @info "Field-camera reconstruction — $(TEST_MODE ? "TEST" : "LIVE"). Ctrl-C to stop."
    scanner, cam = TEST_MODE ? (nothing, nothing) : openLiveCamera()
    frame = 0
    try
        while frame < maxFrames
            field = acquire(cam, frame)
            if field === nothing
                sleep(UPDATE_SECONDS)
                continue
            end
            display(renderFrame(coeffs(field), frame))
            frame += 1
            sleep(UPDATE_SECONDS)
        end
    catch err
        err isa InterruptException || rethrow()
    finally
        isnothing(scanner) || close(scanner)
    end
end

run_demo()
