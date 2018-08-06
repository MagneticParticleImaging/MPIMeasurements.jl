using Unitful

export BrukerRobot
export movePark, moveCenter, mobeAbs, moveRel
export getPos


struct BrukerRobot <: Robot
  connectionName::String
end


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

const xMinBrukerRobot = -85.0Unitful.mm;
const xMaxBrukerRobot = 225.0Unitful.mm;

""" `BrukerCommand(command::String)` """
@compat struct BrukerCommand
  command::String
end

""" Returns `BrukerRobot` """
function brukerRobot(connectionName::String)
  return BrukerRobot(connectionName)
end

""" Move Bruker Robot to center"""
function moveCenter(sd::BrukerRobot)
  _sendCommand(sd,BrukerCommand(center));
end

""" Move Bruker Robot to park"""
function movePark(sd::BrukerRobot)
  _sendCommand(sd,BrukerCommand(park));
end

""" Get Position of Bruker Robot"""
function getPos(sd::BrukerRobot)
  sendCommand(sd,BrukerCommand(pos));
end

""" `moveAbs(sd::BrukerRobot, posX::typeof(1.0Unitful.mm),
  posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm))` """
function moveAbs(sd::BrukerRobot, posX::typeof(1.0Unitful.mm),
  posY::typeof(1.0Unitful.mm), posZ::typeof(1.0Unitful.mm))
  cmd = createMoveCommand(posX,posY,posZ)
  res = _sendCommand(sd, cmd)
end

""" Not Implemented """
function moveRel(sd::BrukerRobot, distX::typeof(1.0Unitful.mm), distY::typeof(1.0Unitful.mm), distZ::typeof(1.0Unitful.mm))
  error("moveRel for ", sd, " not implemented")
end

""" Empty on Purpose"""
function setBrake(sd::BrukerRobot,brake::Bool)
end
getDefaultVelocity(robot::BrukerRobot) = zeros(3)
parkPos(robot::BrukerRobot) = [220.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm]
function setRefVelocity(robot::BrukerRobot, vel::Array{Int64,1})
end

function getMinMaxPosX(robot::BrukerRobot)
    return [xMinBrukerRobot, xMaxBrukerRobot]
end

function createMoveCommand(x::typeof(1.0Unitful.mm),y::typeof(1.0Unitful.mm),z::typeof(1.0Unitful.mm))
  cmd = BrukerCommand("goto $(ustrip(x)),$(ustrip(y)),$(ustrip(z))\n")
end

""" Send Command `sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)`"""
function sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)
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

function _sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)
  (fromStream, inStream, p)=readandwrite(`$(sd.connectionName)`);
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
