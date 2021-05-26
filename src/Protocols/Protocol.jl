
abstract type Protocol end
abstract type ProtocolParams end

name(protocol::Protocol)::String = protocol.name
description(protocol::Protocol)::String = protocol.description
scanner(protocol::Protocol)::String = protocol.scanner
params(protocol::Protocol)::ProtocolParams = protocol.params


@mustimplement init(protocol::Protocol)
@mustimplement execute(protocol::Protocol)
@mustimplement cleanup(protocol::Protocol)


include("RobotBasedProtocol.jl")

