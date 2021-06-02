export Protocol, ProtocolParams, name, description, scanner, params, runProtocol, init, execute, cleanup


abstract type Protocol end
abstract type ProtocolParams end

name(protocol::Protocol)::AbstractString = protocol.name
description(protocol::Protocol)::AbstractString = protocol.description
scanner(protocol::Protocol)::MPIScanner = protocol.scanner
params(protocol::Protocol)::ProtocolParams = protocol.params

"General constructor for all concrete subtypes of Protocol."
function Protocol(protocolName::AbstractString, scanner::MPIScanner)
  configDir_ = configDir(scanner)
  filename = joinpath(configDir_, "Protocols", "$protocolName.toml")

  if isfile(filename)
    toml = TOML.parsefile(filename)
  else
    throw(ProtocolConfigurationError("Could not find a valid configuration for protocol with name `$protocolName` and the derived path `$filename`."))
  end

  if haskey(toml, "name")
    name = pop!(toml, "name")
    if name != protocolName
      throw(ProtocolConfigurationError("The protocol name given in the configuration (`$name`) does not match the name derived from the filename (``$protocolName`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no protocol name given in the configuration file."))
  end

  if haskey(toml, "description")
    description = pop!(toml, "description")
  else 
    throw(ProtocolConfigurationError("There is no protocol description given in the configuration file."))
  end

  if haskey(toml, "targetScanner")
    targetScanner = pop!(toml, "targetScanner")
    if targetScanner != scannerName(scanner)
      throw(ProtocolConfigurationError("The target scanner (`$targetScanner`) for the protocol does not match the given scanner (`$(scannerName(scanner))`)."))
    end
  else 
    throw(ProtocolConfigurationError("There is no target scanner for the protocol given in the configuration file."))
  end

  if haskey(toml, "type")
    protocolType = pop!(toml, "type")
  else 
    throw(ProtocolConfigurationError("There is no protocol type given in the configuration file."))
  end

  params = params_from_dict(getConcreteType(ProtocolParams, protocolType*"Params"), toml)
  ProtocolImpl = getConcreteType(Protocol, protocolType)

  return ProtocolImpl(name=protocolName, description=description, scanner=scanner, params=params)
end
Protocol(protocolName::AbstractString, scannerName::AbstractString) = Protocol(protocolName, MPIScanner(scannerName))

function runProtocol(protocol::Protocol)
  # TODO: Error handling
  init(protocol)
  execute(protocol)
  cleanup(protocol)
end

@mustimplement init(protocol::Protocol)
@mustimplement execute(protocol::Protocol)
@mustimplement cleanup(protocol::Protocol)


include("RobotBasedProtocol.jl")

include("DAQMeasurementProtocol.jl")