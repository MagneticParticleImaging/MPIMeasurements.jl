# Minimal stand-ins for objects that some pure-logic code paths require but never use

# Protocol that only provides a directory for memory-mapped files
mutable struct TempDirProtocol <: Protocol
  dir::String
end
MPIMeasurements.dir(protocol::TempDirProtocol) = protocol.dir

# Protocol that only provides a scanner
struct ScannerProtocol <: Protocol
  scanner::MPIScanner
end

# DriveFieldBuffer requires a ControlSequence, which is not used when complex data is pushed
struct UnusedControlSequence <: MPIMeasurements.ControlSequence end

# RedPitayaDAQ with the given channels; constructing it does not connect to the Red Pitayas,
# that happens in `init`
function unconnectedRedPitayaDAQ(channels = Dict{String, MPIMeasurements.DAQChannelParams}())
  params = MPIMeasurements.RedPitayaDAQParams(channels = channels, ips = String[])
  return RedPitayaDAQ(deviceID = "testRedPitaya", params = params, dependencies = Dict{String, Union{Device, Missing}}())
end
