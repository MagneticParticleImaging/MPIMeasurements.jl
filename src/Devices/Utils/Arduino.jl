export Arduino, sendCommand

abstract type Arduino <: Device end

@mustimplement cmdStart(ard::Arduino)
@mustimplement cmdEnd(ard::Arduino)
@mustimplement cmdDelim(ard::Arduino)
@mustimplement serialDevice(ard::Arduino)

function sendCommand(ard::Arduino, cmdString::String)
  cmd = cmdStart(ard) * cmdString * cmdEnd(ard) * cmdDelim(ard)
  return query(serialDevice(ard), cmd)
end

# TODO maybe return true if command was Received
# Should ACQ be ACK?
function checkACQ(ard::Arduino, reply)
  if reply == "ACQ"
    @info "Command Received"
    return reply;
  else
    @warn "Error, Unknown response" reply
  end
end

function parseBool(ard::Arduino, s::Char)
  if s == '1'
    return true
  elseif s == '0'
    return false
  else
    throw(DomainError(s))
  end
end

Base.@kwdef struct SimpleArduino <: Arduino
  commandStart::String = "!"
  commandEnd::String = "*"
  delim::String = "#"
  sd::SerialDevice
end
