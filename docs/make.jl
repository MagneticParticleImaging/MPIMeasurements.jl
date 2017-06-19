using Documenter, MPIMeasurements

makedocs(
    format = :html,
    modules = [MPIMeasurements],
    sitename = "MPI Measurements",
    authors = "IBI...",
    pages = [
        "Home" => "index.md"
          ],
)

deploydocs(repo   = "github.com/tknopp/MPIMeasurements.jl.git",
           julia  = "release",
           target = "build",
           deps   = nothing,
           make   = nothing)
