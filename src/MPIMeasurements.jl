module MPIMeasurements

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redptaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end

# LibSerialPort currently only supports linux
if is_linux()
  if !isdir(Pkg.dir("LibSerialPort"))
    println("Installing LibSerialPort....")
    Pkg.clone("https://github.com/hofmannmartin/LibSerialPort.jl.git")
    Pkg.build("LibSerialPort")
  end
  using LibSerialPort
  include("SerialDevices/SerialDevices.jl")
end

using Reexport
using IniFile
@reexport using MPIFiles
using PyPlot
@reexport using Redpitaya


include("MPS/MPS.jl")
include("Robots/Robots.jl")
include("DAQ/DAQ.jl")

end # module
