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
            "Framework" => Any[
                "Scanner" => "lib/framework/scanner.md",
                "Device" => "lib/framework/device.md",
                "Sequence" => "lib/framework/sequence.md",
                "Protocol" => "lib/framework/protocol.md",    
            ]
        ],
    ],
)

# deploydocs(repo   = "github.com/MagneticParticleImaging/MPIMeasurements.jl.git",
#           target = "build")
