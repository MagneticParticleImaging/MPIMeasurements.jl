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

function sendCommand(ard::Arduino, cmdString::String, data::AbstractArray)
  cmd = cmdStart(ard) * cmdString * cmdEnd(ard) * cmdDelim(ard)
  return query!(serialDevice(ard), cmd, data)
end

Base.@kwdef struct SimpleArduino <: Arduino
  commandStart::String = "!"
  commandEnd::String = "*"
  delim::String = "#"
  sd::SerialDevice
end
cmdStart(ard::SimpleArduino) = ard.commandStart
cmdEnd(ard::SimpleArduino) = ard.commandEnd
cmdDelim(ard::SimpleArduino) = ard.delim
serialDevice(ard::SimpleArduino) = ard.sd
close(ard::SimpleArduino) = close(ard.sd)