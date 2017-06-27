module MPIMeasurements

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redptaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end

if !isdir(Pkg.dir("LibSerialPort"))
  println("Installing LibSerialPort....")
  Pkg.clone("https://github.com/hofmannmartin/LibSerialPort.jl.git")
  Pkg.checkout("LibSerialPort","julia-0.5-compat")
end

using Reexport
using IniFile
@reexport using MPIFiles
using PyPlot
@reexport using Redpitaya


include("MPS/MPS.jl")
include("Robots/Robots.jl")
include("DAQ/DAQ.jl")
include("SerialDevices/SerialDevices.jl")

end # module
