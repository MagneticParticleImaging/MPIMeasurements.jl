export Arduino, sendCommand

abstract type Arduino <: Device end


@mustimplement cmdStart(ard::Arduino)
@mustimplement cmdEnd(ard::Arduino)
@mustimplement serialDevice(ard::Arduino)

function sendCommand(ard::Arduino, cmdString::String)
  cmd = cmdStart(ard) * cmdString * cmdEnd(ard)
  return query(serialDevice(ard), cmd)
end

function sendCommand(ard::Arduino, cmdString::String, data::AbstractArray)
  cmd = cmdStart(ard) * cmdString * cmdEnd(ard)
  return query!(serialDevice(ard), cmd, data, delimited = true)
end

Base.@kwdef struct SimpleArduino <: Arduino
  commandStart::String = "!"
  commandEnd::String = "*"
  sd::SerialDevice
end
cmdStart(ard::SimpleArduino) = ard.commandStart
cmdEnd(ard::SimpleArduino) = ard.commandEnd
serialDevice(ard::SimpleArduino) = ard.sd
close(ard::SimpleArduino) = close(ard.sd)

macro add_arduino_fields(cmdStart, cmdEnd)
  return esc(quote
    commandStart::String = $cmdStart
    commandEnd::String = $cmdEnd
  end)
end