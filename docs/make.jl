using Documenter
using MPIMeasurements
using Unitful

@warn "Some errors have been suppressed. Should be checked closely!"

makedocs(
    sitename = "MPIMeasurements",
    authors = "Tobias Knopp et al.",
    format = Documenter.HTML(prettyurls = false, size_threshold = 500000,),
    modules = [MPIMeasurements],
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Framework Explanations" => Any[
            "Scanner" => "framework/scanner.md",
            "Devices" => "framework/devices.md",
            "Sequences" => "framework/sequences.md",
            "Protocols" => "framework/protocols.md",
            "Examples" => "framework/examples.md",
        ],
        "Configuration Files / Parameters" => Any[
            "Upgrade Guide" => "config/upgrade.md",
            "Scanner" => "config/scanner.md",
            "Devices" => "config/devices.md",
            "Sequences" => "config/sequence.md",
            "Protocols" => "config/protocols.md",
        ],
        "Library" => Any[
            "Framework" => Any[
                "Scanner" => "lib/framework/scanner.md",
                "Device" => "lib/framework/device.md",
                "Sequence" => "lib/framework/sequence.md",
                "Protocol" => "lib/framework/protocol.md",    
            ],

            "Devices" => Any[
                "Robots" => Any[
                    "Interface" => "lib/base/devices/robots/interface.md",
                    "Isel" => "lib/base/devices/robots/isel.md"
                ],
                "Virtual" => Any[
                    "Serial Port Pool" => "lib/base/devices/virtual/serialportpool.md",
                ]
            ],
        ],
    ],
    warnonly = [:docs_block, :autodocs_block, :cross_references],
)

deploydocs(repo   = "github.com/MagneticParticleImaging/MPIMeasurements.jl.git",
          target = "build")
