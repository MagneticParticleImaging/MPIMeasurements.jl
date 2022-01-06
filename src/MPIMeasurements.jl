module MPIMeasurements

using UUIDs
using Mmap: settings
using Base: Integer
using ThreadPools
using Sockets
using Dates
using Unitful
using TOML
using ProgressMeter
using InteractiveUtils
using Graphics: @mustimplement
using Scratch
using Mmap
using DocStringExtensions
import Plots

using ReplMaker
import REPL
import REPL: LineEdit, REPLCompletions
import REPL: TerminalMenus
import Base.write,  Base.take!, Base.put!, Base.isready, Base.isopen, Base.eltype, Base.close, Base.wait

using Reexport
@reexport using MPIFiles
import MPIFiles: hasKeyAndValue

using RedPitayaDAQServer
import PyTinkerforge

const scannerConfigurationPath = [normpath(string(@__DIR__), "../config")] # Push custom configuration directories here

export addConfigurationPath
addConfigurationPath(path::String) = !(path in scannerConfigurationPath) ? pushfirst!(scannerConfigurationPath, path) : nothing

# circular reference between Scanner.jl and Protocol.jl. Thus we predefine the protocol
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

include("Scanner.jl")
include("Utils/Utils.jl")
include("Devices/Device.jl")

include("Devices/Devices.jl")
include("Protocols/Protocol.jl")
include("Utils/Storage.jl") # Depends on MPIScanner
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
end

end # module
