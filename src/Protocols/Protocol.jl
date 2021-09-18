export Protocol, ProtocolParams, name, description, scanner, params, runProtocol, init, execute, cleanup

abstract type ProtocolParams end

name(protocol::Protocol)::AbstractString = protocol.name
description(protocol::Protocol)::AbstractString = protocol.description
scanner(protocol::Protocol)::MPIScanner = protocol.scanner
params(protocol::Protocol)::ProtocolParams = protocol.params

"General constructor for all concrete subtypes of Protocol."
function Protocol(protocolDict::Dict{String, Any}, scanner::MPIScanner)
  if haskey(protocolDict, "name")
    name = pop!(protocolDict, "name")
  else 
    throw(ProtocolConfigurationError("There is no protocol name given in the configuration."))
  end

  if haskey(protocolDict, "description")
    description = pop!(protocolDict, "description")
  else 
    throw(ProtocolConfigurationError("There is no protocol description given in the configuration."))
  end

  if haskey(protocolDict, "targetScanner")
    targetScanner = pop!(protocolDict, "targetScanner")
    if targetScanner != scannerName(scanner)
      throw(ProtocolConfigurationError("The target scanner (`$targetScanner`) for the protocol does not match the given scanner (`$(scannerName(scanner))`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no target scanner for the protocol given in the configuration."))
  end

  if haskey(protocolDict, "type")
    protocolType = pop!(protocolDict, "type")
  else 
    throw(ProtocolConfigurationError("There is no protocol type given in the configuration."))
  end

  paramsType = getConcreteType(ProtocolParams, protocolType*"Params")
  params = paramsType(protocolDict)
  ProtocolImpl = getConcreteType(Protocol, protocolType)

  return ProtocolImpl(name=name, description=description, scanner=scanner, params=params)
end

function Protocol(protocolName::AbstractString, scanner::MPIScanner)
  configDir_ = configDir(scanner)
  filename = joinpath(configDir_, "Protocols", "$protocolName.toml")

  if isfile(filename)
    protocolDict = TOML.parsefile(filename)
  else
    throw(ProtocolConfigurationError("Could not find a valid configuration for protocol with name `$protocolName` and the derived path `$filename`."))
  end

  if haskey(protocolDict, "name")
    name = protocolDict["name"]
    if name != protocolName
      throw(ProtocolConfigurationError("The protocol name given in the configuration (`$name`) does not match the name derived from the filename (``$protocolName`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no protocol name given in the configuration."))
  end

  return Protocol(protocolDict, scanner)
end

Protocol(protocolName::AbstractString, scannerName::AbstractString) = Protocol(protocolName, MPIScanner(scannerName))
Protocol(protocolDict::Dict{String, Any}, scannerName::AbstractString) = Protocol(protocolDict, MPIScanner(scannerName))

function runProtocol(protocol::Protocol)
  # TODO: Error handling
  init(protocol)
  execute(protocol)
  cleanup(protocol)
end

function askConfirmation(message::AbstractString)
  if isdefined(MPIMeasurements, :Gtk)
    return ask_dialog(message)
  else
    @warn "Gtk.jl failed to load and thus we cannot use it for user confirmation. `askConfirmation` therefore stupidly returns `true` for now."
    return true
  end
end

@mustimplement init(protocol::Protocol)
@mustimplement execute(protocol::Protocol)
@mustimplement cleanup(protocol::Protocol)

include("DAQMeasurementProtocol.jl")
include("MPIMeasurementProtocol.jl")
include("RobotBasedProtocol.jl")
include("RobotBasedSystemMatrixProtocol.jl")
#include("TransferFunctionProtocol.jl")