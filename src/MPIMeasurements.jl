module MPIMeasurements

using Pkg

using Compat
using Reexport
#using IniFile
@reexport using MPIFiles
#@reexport using Redpitaya
@reexport using RedPitayaDAQServer
@reexport using Unitful
@reexport using Unitful.DefaultSymbols
@reexport using TOML
using HDF5
using ProgressMeter
using Sockets
using DelimitedFiles
using LinearAlgebra
using Statistics
using Dates
using Winston, Gtk, Gtk.ShortNames

#using MPISimulations

import RedPitayaDAQServer: currentFrame, currentPeriod, readData, readDataPeriods,
                           setSlowDAC, getSlowADC, enableSlowDAC, readDataSlow
import Base.write
#import PyPlot.disconnect

# abstract supertype for all possible serial devices
@compat abstract type Device end
@compat abstract type Robot end
@compat abstract type GaussMeter end
@compat abstract type SurveillanceUnit end
@compat abstract type TemperatureSensor end

# abstract supertype for all measObj etc.
@compat abstract type MeasObj end
export Device, Robot, GaussMeter, MeasObj

include("DAQ/DAQ.jl")
#include("TransferFunction/TransferFunction.jl") #Moved to MPIFiles
include("Safety/RobotSafety.jl")
include("Safety/KnownSetups.jl")

# LibSerialPort currently only supports linux and julia versions above 0.6
# TODO work this part out under julia-1.0.0
if Sys.isunix() && VERSION >= v"0.6"
  using LibSerialPort
  include("SerialDevices/SerialDevices.jl")
end

#include("Robots/Robots.jl")
include("Scanner/Scanner.jl")
include("Robots/Robots.jl")
include("Sequences/Sequences.jl")

if Sys.isunix() && VERSION >= v"0.6"
  include("GaussMeter/GaussMeter.jl")
  include("TemperatureSensor/TemperatureSensor.jl")
  include("Measurements/Measurements.jl")
  include("SurveillanceUnit/SurveillanceUnit.jl")
end


function __init__()
    Unitful.register(MPIMeasurements)
end


end # module
