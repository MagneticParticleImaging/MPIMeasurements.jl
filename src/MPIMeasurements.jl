#__precompile__()
module MPIMeasurements

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redptaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end

if !isdir(Pkg.dir("TOML"))
  println("Installing TOML...")
  Pkg.clone("https://github.com/wildart/TOML.jl.git")
end

using Compat
using Reexport
using IniFile
@reexport using MPIFiles
@reexport using Redpitaya
@reexport using Unitful
using TOML
# LibSerialPort currently only supports linux and julia versions above 0.6
if is_unix() && VERSION >= v"0.6"
  if !isdir(Pkg.dir("LibSerialPort"))
    println("Installing LibSerialPort....")
    Pkg.clone("https://github.com/hofmannmartin/LibSerialPort.jl.git")
    Pkg.build("LibSerialPort")
  end
  using LibSerialPort
  include("SerialDevices/SerialDevices.jl")
  include("Robots/Robots.jl")
end

import Redpitaya.receive
import Redpitaya.query

if !haskey(ENV,"MPILIB_UI")
  ENV["MPILIB_UI"] = "PyPlot"
end

if ENV["MPILIB_UI"] == "PyPlot"
  using PyPlot
end

include("DAQ/DAQ.jl")
include("TransferFunction/TransferFunction.jl")
include("Scanner/Scanner.jl")
include("GaussMeter/GaussMeter.jl")
include("Measurements/Measurements.jl")


end # module
