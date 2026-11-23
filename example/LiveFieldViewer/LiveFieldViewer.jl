#=
LiveFieldViewer: shows the field the MagSphere measures for the current coil configuration, in the
MagneticFieldViewer of MagneticFieldUI, while GenerateDataMagSphere.jl runs. A separate Julia
process: it receives the settled frame at the end of every configuration that LiveFieldFeed.jl
sends from the measurement process (UDP on 127.0.0.1), so the
GUI never shares a process with the acquisition. Closing or crashing it does not affect the run.

  julia --project=example/LiveFieldViewer -e "using Pkg; Pkg.instantiate()"      (once)
  julia --project=example/LiveFieldViewer example/LiveFieldViewer/LiveFieldViewer.jl [port]

GenerateDataMagSphere.jl starts it by itself with LIVE_FIELD_VIEW = :viewer; with :feed the
measurement only sends and this script can be started (and restarted) by hand at any time.
To try it without hardware, run in a second Julia session with the measurement environment:
  include("example/LiveFieldViewer/LiveFieldFeed.jl"); feed = LiveFieldFeed.startDemo()

Field reconstruction
  Each frame (3 field components at the 114 sensors) is expanded into solid spherical
  harmonics up to degree L by least squares on the sensors with a valid reading. The 114
  MagSphere positions form a spherical t-design up to degree 14 (quadrature exact to ~1e-9
  for L <= 7), so with all sensors valid this is the t-design quadrature of
  MPIHarmonicMagneticFields.magneticField up to round-off (same normalization and solid
  conversion; on a known test field both reproduce it to < 1e-8 T inside the sphere). Invalid
  (NaN) sensors are left out instead of turning the whole expansion into NaN.

Updates keep the viewer's state: slice position, L, FOV, colormap and the "keep colour
limits" option stay as set, only the coefficients change. The window title shows the
measurement status, the newest frame and when data stop arriving.
=#

using Gtk4
using MagneticFieldUI
using MPIHarmonicMagneticFields
using SphericalHarmonicExpansions
using Sockets
using LinearAlgebra
using Printf
using Dates

include("LiveFieldPacket.jl")

const L_MAX = 7               # expansion degree, see the header
const REFRESH_MS = 500        # how often the GUI looks for a new frame
const STALE_AFTER_S = 5.0     # datagrams older than this: measurement stopped or feed off
const FRAME_STALE_AFTER_S = 3.0

# --- Spherical-harmonic fit ---------------------------------------------------

"Real spherical harmonics up to degree L at the sensor directions, for one sensor layout."
struct SphereFit
  positions::Matrix{Float32}   # 3×n, m, as received (to notice a changed layout)
  basis::Matrix{Float64}       # n × (L+1)², Y_lm at the unit directions, order l = 0..L, m = -l..l
  L::Int
  radius::Float64              # m
  center::Vector{Float64}      # m
end

function SphereFit(positions::Matrix{Float32}; L::Int = L_MAX)
  n = size(positions, 2)
  P = Float64.(positions)
  center = zeros(3)            # MagSphere positions are given in the sphere frame
  r = vec(sqrt.(sum(abs2, P .- center; dims = 1)))
  radius = sum(r) / n
  maximum(abs.(r .- radius)) < 1e-3 * radius ||
    @warn "Sensor radii vary by up to $(round(maximum(abs.(r .- radius)) * 1e3, digits = 2)) mm; " *
          "the expansion assumes all sensors on one sphere."
  L = min(L, floor(Int, sqrt(n)) - 1)      # never more unknowns than sensors
  dirs = (P .- center) ./ r'
  @polyvar x y z
  Y = [ylm(l, m, x, y, z) for l in 0:L for m in -l:l]
  basis = [Float64(Y[j]((x, y, z) => (dirs[1, k], dirs[2, k], dirs[3, k]))) for k in 1:n, j in eachindex(Y)]
  return SphereFit(positions, basis, L, radius, center)
end

"""
    fitField(fit, field) -> (coefficients or nothing, number of valid sensors)

Solid spherical-harmonic coefficients (MagneticFieldCoefficients, one patch) of a 3×n field
in T. `nothing` if too few sensors are valid for degree `fit.L`.
"""
function fitField(fit::SphereFit, field::AbstractMatrix{<:Real})
  valid = [all(isfinite, view(field, :, s)) for s in axes(field, 2)]
  nValid = count(valid)
  nValid >= size(fit.basis, 2) || return nothing, nValid
  C = fit.basis[valid, :] \ permutedims(Float64.(field[:, valid]))   # (L+1)² × 3
  coeffs = Array{SphericalHarmonicCoefficients, 2}(undef, 3, 1)
  for j in 1:3
    c = SphericalHarmonicCoefficients(C[:, j])
    c.R = fit.radius
    normalize!(c, fit.radius)
    solid!(c)
    coeffs[j, 1] = c
  end
  return MagneticFieldCoefficients(coeffs, fit.radius, fit.center), nValid
end

# --- Viewer -----------------------------------------------------------------------

mutable struct LiveView
  viewer::MagneticFieldViewer
  port::Int
  fit::Union{SphereFit, Nothing}
  latest::Union{LiveFieldPacket, Nothing}   # newest datagram, set by the receiver task
  latestAt::Float64                         # time() it arrived
  shownCount::Int                           # frameCount of the frame on screen
  shownAt::Float64
  ready::Bool                               # warm-up done
  initialized::Bool                         # first frame shown
  errors::Int
  @atomic open::Bool
end

"""
Draw a synthetic field once in a hidden viewer widget. The first draw compiles the plotting
code (~2 min); doing it at start-up keeps the window from freezing on the first real frame.
"""
function warmUp()
  n = 114                                    # Fibonacci sphere of MagSphere size and radius
  k = 0:n-1
  z = 1 .- 2 .* (k .+ 0.5) ./ n
  ϕ = π * (3 - sqrt(5)) .* k
  ρ = sqrt.(1 .- z .^ 2)
  P = Float32.(0.09 .* permutedims(hcat(ρ .* cos.(ϕ), ρ .* sin.(ϕ), z)))
  coeffs, _ = fitField(SphereFit(P), 0.1f0 .* P .* Float32[1, 1, -2])
  w = MagneticFieldUI.MagneticFieldViewerWidget()
  MagneticFieldUI.initViewer(w, coeffs)
  MagneticFieldUI.updateData!(w, coeffs)
  w.updating = true
  MagneticFieldUI.updateIntersection(w)
  MagneticFieldUI.updatePlots(w)
end

"Put new coefficients on screen, keeping everything the user has set in the viewer."
function show!(lv::LiveView, coeffs::MagneticFieldCoefficients)
  m = lv.viewer.mf
  if !lv.initialized
    MagneticFieldUI.initViewer(m, coeffs)
    MagneticFieldUI.updateData!(m, coeffs)        # first frame: set up ranges, slices, colours
    lv.initialized = true
    return
  end
  m.updating = true                               # keeps the slice callbacks from re-plotting
  try
    m.coeffsInit = deepcopy(coeffs)               # the viewer's "reset" returns to the newest frame
    m.coeffs = coeffs
    m.fv.centerFFP = false                        # live coefficients carry no FFP
    MagneticFieldUI.updateIntersection(m)         # expand around the current intersection
    MagneticFieldUI.updatePlots(m)
  finally
    m.updating = false
  end
end

function setTitle!(lv::LiveView, text::AbstractString)
  set_gtk_property!(lv.viewer.w, :title, "MagSphere live field · " * text)
end

ago(t) = @sprintf("%.0f s", time() - t)

"One GUI refresh: called by the GLib main loop every REFRESH_MS."
function tick!(lv::LiveView)
  (@atomic lv.open) || return false
  lv.ready || return true
  try
    p = lv.latest
    status = isnothing(p) || isempty(p.status) ? "" : " · " * p.status
    if isnothing(p)
      setTitle!(lv, "waiting for the measurement on port $(lv.port)")
    elseif time() - lv.latestAt > STALE_AFTER_S
      setTitle!(lv, "measurement not sending for $(ago(lv.latestAt))" * status)
    elseif size(p.field, 2) == 0
      setTitle!(lv, "waiting for the first MagSphere frame" * status)
    elseif p.frameCount != lv.shownCount
      if isnothing(lv.fit) || lv.fit.positions != p.positions
        lv.fit = SphereFit(p.positions)
      end
      coeffs, nValid = fitField(lv.fit, p.field)
      nInvalid = size(p.field, 2) - nValid
      if isnothing(coeffs)
        setTitle!(lv, "only $nValid valid sensors, frame not shown" * status)
      else
        show!(lv, coeffs)
        lv.shownCount = p.frameCount
        lv.shownAt = time()
        Bmax = maximum(s -> all(isfinite, view(p.field, :, s)) ? norm(view(p.field, :, s)) : 0.0, axes(p.field, 2))
        setTitle!(lv, @sprintf("frame %d · %s · max |B| at sensors %.2f mT", p.frameCount,
                               Dates.format(now(), "HH:MM:SS"), Bmax * 1e3) *
                      (nInvalid > 0 ? " · $nInvalid invalid sensors" : "") * status)
      end
    elseif time() - lv.shownAt > FRAME_STALE_AFTER_S
      setTitle!(lv, "no new MagSphere frame for $(ago(lv.shownAt))" * status)
    end
  catch e
    lv.errors += 1
    lv.errors <= 3 && @error "Live field viewer: refresh failed" exception = (e, catch_backtrace())
    lv.errors == 3 && @warn "Further refresh errors are not reported."
  end
  return true
end

function receive!(lv::LiveView, sock::UDPSocket)
  while @atomic lv.open
    bytes = try
      recv(sock)
    catch e
      (@atomic lv.open) || break
      @error "Live field viewer: receiving failed" exception = e
      sleep(1.0)
      continue
    end
    p = decodeLiveFieldPacket(bytes)
    isnothing(p) && continue
    lv.latest = p
    lv.latestAt = time()
  end
end

"Open the viewer window and start listening; returns at once (GTK must be running, as in the REPL)."
function startViewer(port::Int = LIVE_FIELD_DEFAULT_PORT)
  sock = UDPSocket()
  bind(sock, ip"127.0.0.1", port) ||
    error("Port $port is in use. Is another live field viewer already open?")
  viewer = MagneticFieldViewer()
  lv = LiveView(viewer, port, nothing, nothing, 0.0, -1, 0.0, false, false, 0, true)
  setTitle!(lv, "preparing the plots (the first start compiles them, about 2 min)")
  Gtk4.GLib.g_idle_add() do
    try
      warmUp()
    catch e
      @warn "Live field viewer: warm-up failed, the first frame will take longer" exception = e
    end
    lv.latest = nothing             # from before the warm-up blocked the receiver: outdated
    lv.ready = true
    setTitle!(lv, "waiting for the measurement on port $port")
    return false
  end

  signal_connect(viewer.w, "close-request") do _
    @atomic lv.open = false
    close(sock)                     # ends the receiver
    return false                    # let the window close
  end
  @async receive!(lv, sock)
  Gtk4.GLib.g_timeout_add(() -> tick!(lv), REFRESH_MS)
  @info "Live field viewer listening on 127.0.0.1:$port"
  return lv
end

"Run the viewer as a script: open it and keep GTK running until the window is closed."
function main(port::Int = LIVE_FIELD_DEFAULT_PORT)
  lv = startViewer(port)
  if !isinteractive()               # the REPL runs GTK's loop by itself
    @async Gtk4.GLib.glib_main()
    Gtk4.GLib.waitforsignal(lv.viewer.w, :close_request)
  end
  return lv
end

if abspath(PROGRAM_FILE) == @__FILE__
  main(isempty(ARGS) ? LIVE_FIELD_DEFAULT_PORT : parse(Int, ARGS[1]))
end
