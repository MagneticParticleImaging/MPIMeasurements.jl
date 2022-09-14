module MPIMeasurements

using UUIDs
using Mmap: settings
using Base: Integer
import Base.Iterators: flatten
using ThreadPools
using Sockets
using Dates
using Unitful
using TOML
using ProgressMeter
using InteractiveUtils
using Graphics: @mustimplement
using Mmap
using StringEncodings
using DocStringExtensions
using MacroTools

using ReplMaker
import REPL
import REPL: LineEdit, REPLCompletions
import REPL: TerminalMenus
import Base.write,  Base.take!, Base.put!, Base.isready, Base.isopen, Base.eltype, Base.close, Base.wait, Base.length
import Base: ==, isequal

using Reexport
@reexport using MPIFiles
import MPIFiles: hasKeyAndValue, 
    acqGradient, acqNumPeriodsPerFrame, acqNumPeriodsPerPatch, acqNumPatches, acqOffsetField,
    acqNumFrames, acqNumAverages,
    dfBaseFrequency, dfCycle, dfDivider, dfNumChannels, dfPhase, dfStrength, dfWaveform,
    rxBandwidth, rxNumChannels, rxNumSamplingPoints

using RedPitayaDAQServer
import PyTinkerforge

const scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here

export addConfigurationPath
addConfigurationPath(path::String) = !(path in scannerConfigurationPath) ? pushfirst!(scannerConfigurationPath, path) : nothing

# Circular reference between Scanner.jl and Protocol.jl. Thus we predefine the protocol
"""
Abstract type for all protocols

Every protocol has to implement its own protocol struct which identifies it.
A concrete implementation should contain e.g. the handle to the datastore
or internal variables.
The device struct must at least have the fields `name`, `description`,
`scanner` and `params` and all other fields should have default values.
"""
abstract type Protocol end

# circular reference between Device.jl and Utils.jl. Thus we predefine the Device
"""
Abstract type for all devices

Every device has to implement its own device struct which identifies it.
A concrete implementation should contain e.g. the handle to device ressources
or internal variables.
The device struct must at least have the fields `deviceID`, `params` and `dependencies` and
all other fields should have default values.
"""
abstract type Device end

include("Sequences/Sequence.jl")
include("Scanner.jl")
include("Devices/Device.jl")
include("Utils/Utils.jl")


include("Protocols/Storage/MDF.jl") # Defines stuff needed in devices
include("Protocols/Storage/MeasurementState.jl")
include("Devices/Devices.jl")
include("Protocols/Protocol.jl")
include("Protocols/Storage/ProducerConsumer.jl") # Depends on MPIScanner and Protocols
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
