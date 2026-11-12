# Minimal stand-ins for objects that some pure-logic code paths require but never use

# Protocol that only provides a directory for memory-mapped files
mutable struct TempDirProtocol <: Protocol
  dir::String
end
MPIMeasurements.dir(protocol::TempDirProtocol) = protocol.dir

# DriveFieldBuffer requires a ControlSequence, which is not used when complex data is pushed
struct UnusedControlSequence <: MPIMeasurements.ControlSequence end
