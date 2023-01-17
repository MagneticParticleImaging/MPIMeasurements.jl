using Documenter
using MPIMeasurements

makedocs(
    sitename = "MPIMeasurements",
    authors = "Tobias Knopp et al.",
    format = Documenter.HTML(prettyurls = false),
    modules = [MPIMeasurements],
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Framework" => Any[
            "Scanner" => "framework/scanner.md",
            "Devices" => "framework/devices.md",
            "Sequences" => "framework/sequences.md",
            "Protocols" => "framework/protocols.md",
            "Examples" => "framework/examples.md",
        ],
        "Library" => Any[
            "Public" => "lib/public.md",
            "Internals" => map(
                s -> "lib/internals/$(s)",
                sort(readdir(normpath(@__DIR__, "src/lib/internals")))
            ),
        ],
    ],
)

# deploydocs(repo   = "github.com/MagneticParticleImaging/MPIMeasurements.jl.git",
#           target = "build")
