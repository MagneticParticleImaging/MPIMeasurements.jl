module MPIMeasurements

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redptaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end

using Reexport
using IniFile
@reexport using MPIFiles
using PyPlot
@reexport using Redpitaya


include("MPS/MPS.jl")

end # module
