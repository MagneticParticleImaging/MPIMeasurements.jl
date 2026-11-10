module MPIMeasurements

using UUIDs
using Mmap: settings
using Base: Integer
import Base.Iterators: flatten
using ThreadPools
using Sockets
using DataStructures
using Dates
using Unitful
using TOML
using ProgressMeter
using InteractiveUtils
using Mmap
using Scratch
using StringEncodings
using StyledStrings
using Statistics
using DocStringExtensions
using MacroTools
using LibSerialPort
using UnicodePlots
using LinearAlgebra
using HDF5
using FFTW
using NaturalSort
using RelocatableFolders

using ReplMaker
import REPL
import REPL: LineEdit, REPLCompletions
import REPL: TerminalMenus
import Base.write, Base.take!, Base.put!, Base.isready, Base.isopen, Base.eltype, Base.close, Base.wait, Base.length, Base.push!
import Base: ==, isequal, hash, isfile, push!, pop!, empty!, getindex, setindex!, firstindex, lastindex, length, iterate, delete!, deleteat!, keys, haskey, values

# Reexporting MPIFiles is disliked by Aqua since there are undefined exports. Therefore, I disabled reexporting here.
#using Reexport
#@reexport using MPIFiles

using MPIFiles
import MPIFiles: hasKeyAndValue, 
    acqGradient, acqNumPeriodsPerFrame, acqNumPeriodsPerPatch, acqNumPatches, acqOffsetField,
    acqNumFrames, acqNumAverages,
    dfBaseFrequency, dfCycle, dfDivider, dfNumChannels, dfPhase, dfStrength, dfWaveform,
    rxBandwidth, rxNumChannels, rxNumSamplingPoints

using RedPitayaDAQServer
const DEFAULT_SCANNER_CONFIG_PATH = @path joinpath(@__DIR__, "..", "config")
const scannerConfigurationPath = AbstractString[DEFAULT_SCANNER_CONFIG_PATH] # Push custom configuration directories here

export addConfigurationPath
addConfigurationPath(path) = !(path in scannerConfigurationPath) ? pushfirst!(scannerConfigurationPath, path) : nothing


include("Utils/Mustimplement.jl")
include("Sequences/Sequence.jl")
include("Devices/Device.jl")
include("Scanner.jl")
include("Utils/Utils.jl")

include("Protocols/Storage/MDF.jl") # Defines stuff needed in devices
include("Protocols/Storage/MeasurementState.jl")
include("Devices/Devices.jl")
include("Protocols/Protocol.jl")
include("Protocols/Storage/ChainableBuffer.jl")
include("Protocols/Storage/ProducerConsumer.jl") # Depends on MPIScanner and Protocols
include("Utils/MmapFiles.jl")
include("Utils/Console/Console.jl")

"""
    $(SIGNATURES)

Initialize configuration paths with the package and enable MPI REPL mode.
"""
function __init__()
  defaultScannerConfigurationPath = joinpath(homedir(), ".mpi", "Scanners")
  if isdir(defaultScannerConfigurationPath)
    addConfigurationPath(defaultScannerConfigurationPath)
  end

  mpi_mode_enable()
  device_mode_enable()
  atexit(() -> close(mpi_repl_mode)) # Make sure that an activated scanner is always closed
end

end # module
