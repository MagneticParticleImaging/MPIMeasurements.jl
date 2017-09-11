using Graphics: @mustimplement

export moveAbs, moveAbsUnsafe, moveRelUnsafe, movePark, moveCenter
export AbstractRobot, Robot

include("Positions.jl")
include("RobotSafety.jl")

@compat abstract type AbstractRobot end

# The following methods need to be implemented by a robot
@mustimplement moveAbs(robot::AbstractRobot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
@mustimplement moveRel(robot::AbstractRobot, distX::typeof(1.0u"mm"),
    distY::typeof(1.0u"mm"), distZ::typeof(1.0u"mm"))
@mustimplement movePark(robot::AbstractRobot)
@mustimplement moveCenter(robot::AbstractRobot)

""" `moveAbs(robot::AbstractRobot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbs(robot::AbstractRobot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
  end
  coordsTable = checkCoords(setup, xyzPos)
  moveAbsUnsafe(robot,xyzPos)
end

""" `moveAbsUnsafe(robot::AbstractRobot, xyzPos::Vector{typeof(1.0u"mm")})` """
function moveAbsUnsafe(robot::AbstractRobot, xyzPos::Vector{typeof(1.0u"mm")})
    if length(xyzPos)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
    end
    moveAbs(robot,xyzPos[1],xyzPos[2],xyzPos[3])
end

# """ `moveRel(robot::AbstractRobot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})` """
# function moveRel(robot::AbstractRobot, setup::RobotSetup, xyzDist::Vector{typeof(1.0u"mm")})
#   if length(xyzDist)!=3
#     error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
#   end
#   coordsTable = checkCoords(setup, xyzDist)
#   moveRelUnsafe(robot,xyzDist)
# end

""" `moveRelUnsafe(robot::AbstractRobot, xyzDist::Vector{typeof(1.0u"mm")})` """
function moveRelUnsafe(robot::AbstractRobot, xyzDist::Vector{typeof(1.0u"mm")})
    if length(xyzDist)!=3
      error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzDist))
    end
    moveRel(robot,xyzDist[1],xyzDist[2],xyzDist[3])
end

include("IselRobot.jl")
include("BrukerRobot.jl")
include("DummyRobot.jl")

function Robot(params::Dict)
  if params["type"] == "Dummy"
    return DummyRobot()
  elseif params["type"] == "Isel"
    return IselRobot(params["connection"],minVel=params["minVel"],maxVel=params["maxVel"],
    minAcc=params["minAcc"],maxAcc=params["maxAcc"],minFreq=params["minFreq"],
    maxFreq=params["maxFreq"],stepsPerTurn=params["stepsPerTurn"],gearSlope=params["gearSlope"],
    defaultVel=params["defaultVel"],defCenterPos=params["defCenterPos"],defParkPos=params["defParkPos"])
  elseif params["type"] == "Bruker"
    return BrukerRobot(params["connection"])
  else
    error("Cannot create Robot!")
  end
end

include("Tour.jl")
