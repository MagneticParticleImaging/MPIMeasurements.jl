using Graphics: @mustimplement

export moveAbs

include("Positions.jl")
include("RobotSafety.jl")

@compat abstract type AbstractRobot end

# The following methods need to be implemented by a robot
@mustimplement moveAbs(robot::AbstractRobot, posX::typeof(1.0u"mm"),
  posY::typeof(1.0u"mm"), posZ::typeof(1.0u"mm"))
@mustimplement movePark(robot::AbstractRobot)

""" `moveAbs(scanner::BaseScanner, xyzPos::Vector{typeof(1.0u"mm")})` Robot MidLevel """
function moveAbs(robot::AbstractRobot, setup::RobotSetup, xyzPos::Vector{typeof(1.0u"mm")})
  if length(xyzPos)!=3
    error("position vector xyzPos needs to have length = 3, but has length: ",length(xyzPos))
  end

  coordsTable = checkCoords(setup, xyzPos)

  moveAbs(robot,xyzPos[1],xyzPos[2],xyzPos[3])
end

include("IselRobot.jl")
include("BrukerRobot.jl")
include("DummyRobot.jl")
#include("RobotMidLevel.jl")

include("Tour.jl")
