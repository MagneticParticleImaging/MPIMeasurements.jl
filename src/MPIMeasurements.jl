__precompile__()
module MPIMeasurements

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redpitaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("RedPitayaDAQServer"))
  println("Installing RedPitayaDAQServer...")
  Pkg.clone("https://github.com/tknopp/RedPitayaDAQServer.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end
#=
if !isdir(Pkg.dir("MPISimulations"))
  println("Installing MPISimulations...")
  Pkg.clone("https://github.com/tknopp/MPISimulations.jl.git")
end
=#
if !isdir(Pkg.dir("TOML"))
  println("Installing TOML...")
  Pkg.clone("https://github.com/wildart/TOML.jl.git")
end



using Compat
using Reexport
#using IniFile
@reexport using MPIFiles
#@reexport using Redpitaya
@reexport using RedPitayaDAQServer
@reexport using Unitful
@reexport using TOML
using HDF5
using ProgressMeter
#using MPISimulations

import Redpitaya: receive, query
import RedPitayaDAQServer: currentFrame, currentPeriod, readData, readDataPeriods,
                           setSlowDAC, getSlowADC, enableSlowDAC
import Base.write
#import PyPlot.disconnect

# abstract supertype for all possible serial devices
@compat abstract type Device end
@compat abstract type Robot end
@compat abstract type GaussMeter end
@compat abstract type SurveillanceUnit end

# abstract supertype for all measObj etc.
@compat abstract type MeasObj end
export Device, Robot, GaussMeter, MeasObj

include("DAQ/DAQ.jl")
include("TransferFunction/TransferFunction.jl")
include("Safety/RobotSafety.jl")

# LibSerialPort currently only supports linux and julia versions above 0.6
if is_unix() && VERSION >= v"0.6"
  if !isdir(Pkg.dir("LibSerialPort"))
    println("Installing LibSerialPort....")
    Pkg.clone("https://github.com/hofmannmartin/LibSerialPort.jl.git")
    Pkg.build("LibSerialPort")
  end
  using LibSerialPort
  include("SerialDevices/SerialDevices.jl")
end

#include("Robots/Robots.jl")
include("Scanner/Scanner.jl")
include("Robots/Robots.jl")
include("Sequences/Sequences.jl")

if is_unix() && VERSION >= v"0.6"
  include("GaussMeter/GaussMeter.jl")
  include("Measurements/Measurements.jl")
  include("SurveillanceUnit/SurveillanceUnit.jl")
end


function __init__()
    Unitful.register(MPIMeasurements)
end


end # module
