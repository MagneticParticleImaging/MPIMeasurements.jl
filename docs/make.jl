using Documenter
using MPIMeasurements

makedocs(
    sitename = "MPIMeasurements",
    authors = "Tobias Knopp et al.",
    format = Documenter.HTML(prettyurls = false),
    modules = [MPIMeasurements],
    pages = [
        "Home" => "index.md",
        "Manual" => Any[
            "Guide" => "man/guide.md",
            "Devices" => "man/devices.md",
            "Protocols" => "man/protocols.md",
            "Sequences" => "man/sequences.md",
            "Examples" => "man/examples.md",
        ],
        "Library" => Any[
            "Public" => "lib/public.md",
            "Internals" => map(
                s -> "lib/internals/$(s)",
                sort(readdir(normpath(@__DIR__, "src/lib/internals")))
            ),
        ],
        "contributing.md",
    ],
)

# deploydocs(repo   = "github.com/MagneticParticleImaging/MPIMeasurements.jl.git",
#           target = "build")
