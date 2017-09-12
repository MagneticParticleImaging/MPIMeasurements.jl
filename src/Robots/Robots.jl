using Graphics: @mustimplement

export moveAbs, moveAbsUnsafe, moveRelUnsafe, movePark, moveCenter
export Robot

include("Positions.jl")

# The following methods need to be implemented by a robot
@mustimplement moveAbs(robot::Robot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
@mustimplement moveRel(robot::Robot, distX::typeof(1.0u"mm"),
    distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
@mustimplement movePark(robot::Robot)
@mustimplement moveCenter(robot::Robot)
@mustimplement setBrake(robot::Robot,brake::Bool)

""" `moveAbs(robot::Robot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbs(robot::Robot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
  end
  coordsTable = checkCoords(setup, xyzPos)
  moveAbsUnsafe(robot,xyzPos)
end

""" `moveAbsUnsafe(robot::Robot, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbsUnsafe(robot::Robot, xyzPos::Vector{typeof(1.0u"mm")})
    if length(xyzPos)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
    end
    moveAbs(robot,xyzPos[1],xyzPos[2],xyzPos[3])
end

# """ `moveRel(robot::Robot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})` """
# function moveRel(robot::Robot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})
#   if length(xyzDist)!=3
#     error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
#   end
#   coordsTable = checkCoords(setup, xyzDist)
#   moveRelUnsafe(robot,xyzDist)
# end

""" `moveRelUnsafe(robot::Robot, xyzDist::Vector{typeof(1.0u"mm")})` """
function moveRelUnsafe(robot::Robot, xyzDist::Vector{typeof(1.0u"mm")})
    if length(xyzDist)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
    end
    moveRel(robot,xyzDist[1],xyzDist[2],xyzDist[3])
end

if is_unix() && VERSION >= v"0.6"
  include("IselRobot.jl")
end

include("BrukerRobot.jl")
include("DummyRobot.jl")

function Robot(params::Dict)
  if params["type"] == "Dummy"
    return DummyRobot()
  elseif params["type"] == "Isel"
    return IselRobot(params)
  elseif params["type"] == "Bruker"
    return BrukerRobot(params["connection"])
  else
    error("Cannot create Robot!")
  end
end

include("Tour.jl")
