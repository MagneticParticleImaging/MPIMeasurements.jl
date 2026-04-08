using Pkg

println("="^70)
println("Running Frequency Filtering Tests")
println("="^70)

Pkg.activate(".")
using MPIMeasurements

required_packages = ["Test", "FFTW", "Statistics"]
for pkg in required_packages
    if !haskey(Pkg.project().dependencies, pkg)
        Pkg.add(pkg)
    end
end

include("Protocols/BufferTests.jl")

println("="^70)
println("All tests passed!")
println("="^70)
