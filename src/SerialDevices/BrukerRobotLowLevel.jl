using Unitful

export BrukerRobot, brukerRobot
export movePark, moveCenter, mobeAbs, moveRel
export getPos

@compat abstract type BrukerRobot <: Device end

# Usefull links
# http://unix.stackexchange.com/questions/87831/how-to-send-keystrokes-f5-from-terminal-to-a-process
#
# https://github.com/JuliaLang/julia/pull/6948
#
# Kind of deprecated:
# http://blog.leahhanson.us/post/julia/julia-commands.html

const center="center\n";
const park="park\n";
const pos="pos\n";
const quit="quit\n"
const exit="exit\n"
const err="err?\n"

""" `BrukerCommand(command::String)` """
@compat struct BrukerCommand
  command::String
end

""" Returns `ServerDevice{BrukerRobot}` """
function brukerRobot(connectionName::String)
  return ServerDevice{BrukerRobot}(connectionName)
end

""" Move Bruker Robot to center"""
function moveCenter(sd::ServerDevice{BrukerRobot})
  _sendCommand(sd,BrukerCommand(center));
end

""" Move Bruker Robot to park"""
function movePark(sd::ServerDevice{BrukerRobot})
  _sendCommand(sd,BrukerCommand(park));
end

""" Get Position of Bruker Robot"""
function getPos(sd::ServerDevice{BrukerRobot})
  sendCommand(sd,BrukerCommand(pos));
end

""" `moveAbs(sd::ServerDevice{BrukerRobot}, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))` """
function moveAbs(sd::ServerDevice{BrukerRobot}, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
  cmd = createMoveCommand(posX,posY,posZ)
  res = _sendCommand(sd, cmd)
end

""" Not Implemented """
function moveRel(sd::ServerDevice{BrukerRobot}, distX::typeof(1.0u"mm"), distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
  error("moveRel for ", sd, " not implemented")
end

function createMoveCommand(x::typeof(1.0u"mm"),y::typeof(1.0u"mm"),z::typeof(1.0u"mm"))
  cmd = BrukerCommand("goto $(ustrip(x)),$(ustrip(y)),$(ustrip(z))\n")
end

""" Send Command `sendCommand(sd::ServerDevice{BrukerRobot}, brukercmd::BrukerCommand)`"""
function sendCommand(sd::ServerDevice{BrukerRobot}, brukercmd::BrukerCommand)
  (result, startmovetime, endmovetime)= _sendCommand(sd, brukercmd);
  if result=="0\n"
      return true;
  elseif length(split(result,","))==3
      println("$(brukercmd.command) returned position: $(result)")
      return true;
  elseif  result=="?\n"
      println("$(brukercmd.command) is unknown! Try again...")
      return false;
  elseif result=="!\n"
      println("Error during command $(brukercmd.command) execution. ")
      return false;
  else
      println("$(brukercmd.command) has unexpected result $(result)")
      return false;
  end
end

function _sendCommand(sd::ServerDevice{BrukerRobot}, brukercmd::BrukerCommand)
  (fromStream, inStream, p)=readandwrite(`$(sd)`);
  #(fromStream, inStream, p)=readandwrite(`cat`);
  startmovetime=now(Dates.UTC);
  writetask=write(inStream,brukercmd.command)
  writetaskexit=write(inStream,exit)
  readtask=@async readavailable(fromStream)
  wait(readtask)
  endmovetime=now(Dates.UTC);
  if readtask.state==:done
    return (ascii(String(readtask.result)), startmovetime, endmovetime);
  else
    println("end $(readTask.state)")
    println("end $(readTask.exception)")
    return readtask.exception;
  end
end
