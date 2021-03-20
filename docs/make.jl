using Documenter, MPIMeasurements

makedocs(
    format = Documenter.HTML(prettyurls = false),
    modules = [MPIMeasurements],
    sitename = "MPI Measurements",
    authors = "Tobias Knopp et al.",
    pages = [
        "Home" => "index.md"
    ]
)

deploydocs(repo   = "github.com/MagneticParticleImaging/MPIMeasurements.jl.git",
          target = "build")
           