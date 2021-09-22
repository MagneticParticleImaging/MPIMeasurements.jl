using Base: Integer

export RobotBasedProtocol, positions, postMoveWaitTime, numCooldowns, robotVelocity, switchBrakes, preMoveAction, postMoveAction

abstract type RobotBasedProtocol <: Protocol end
abstract type RobotBasedProtocolParams <: ProtocolParams end

positions(protocol::RobotBasedProtocol)::Union{Positions, Missing} = protocol.params.positions
postMoveWaitTime(protocol::RobotBasedProtocol)::typeof(1.0u"s") = protocol.params.postMoveWaitTime
numCooldowns(protocol::RobotBasedProtocol)::Integer = protocol.params.numCooldowns
robotVelocity(protocol::RobotBasedProtocol)::typeof(1.0u"m/s") = protocol.params.robotVelocity
switchBrakes(protocol::RobotBasedProtocol)::Bool = protocol.params.switchBrakes

function execute(protocol::RobotBasedProtocol)
  scanner_ = scanner(protocol)
  robot = getRobot(scanner_)

  positions_ = positions(protocol)
  vel = robotVelocity(protocol)
  switchBrakes_ = switchBrakes(protocol)

  enable(robot)
  if !isReferenced(robot)
    moveRel(robot, RobotCoords([1.0u"mm", 1.0u"mm", 1.0u"mm"]))
    doReferenceDrive(robot)
  end
  movePark(robot)
  
  for (index, pos) in enumerate(positions_)
    for coord in pos
      @debug coord
    end
    # Cooldown pause
    numCooldowns_ = numCooldowns(protocol)
    if numCooldowns_ > 0 && index == round(Int, length(positions)/numCooldowns_)
      println("Cooled down? Enter \"yes\"")
      while readline() != "yes"
        println("Cooled down? Enter \"yes\"")
      end
    end

    @debug pos

    preMoveAction(protocol, upreferred.(pos))
    moveAbs(robot, upreferred.(pos), vel)
    sleep(ustrip(u"s", postMoveWaitTime(protocol)))

    # if hasBrake(robot) && switchBrakes_
    #   setBrake(robot, false)
    # end

    postMoveAction(protocol, pos)

    # if hasBrake(robot) && switchBrakes_
    #   setBrake(robot, true)
    # end
  end

  movePark(robot)
end

@mustimplement preMoveAction(protocol::RobotBasedProtocol)
@mustimplement postMoveAction(protocol::RobotBasedProtocol)

"Create the params struct from a dict. Typically called during scanner instantiation."
function createRobotBasedProtocolParams(ProtocolType::DataType, dict::Dict{String, Any})
  @debug "" ProtocolType dict
  for (key, value) in dict
    println("$key => $value")
  end
  @assert ProtocolType <: RobotBasedProtocolParams "The supplied type `$type` cannot be used for creating robot based protocol params, since it does not inherit from `ProtocolType`."
  
  # Split between main section fields and channels, which are dictionaries
  positionsDict = Dict{String, Any}()
  for (key, value) in dict["positions"]
    key = String([i == 1 ? uppercase(c) : c for (i, c) in enumerate(key)]) # No indexing to prevent possible errors with unicode
    positionsDict["positions"*key] = tryuparse.(value)
  end

  # Remove key in order to process the rest with the standard function
  delete!(dict, "positions")
  
  splattingDict = dict_to_splatting(dict)
  splattingDict[:positions] = Positions(positionsDict)

  try
    return ProtocolType(;splattingDict...)
  catch e
    if e isa UndefKeywordError
      throw(ScannerConfigurationError("The required field `$(e.var)` is missing in your configuration "*
                                      "for a device with the params type `$ProtocolType`."))
    elseif e isa MethodError
      @warn e.args e.world e.f
      throw(ScannerConfigurationError("A required field is missing in your configuration for a device "*
                                      "with the params type `$ProtocolType`. Please check "*
                                      "the causing stacktrace."))
    else
      rethrow()
    end
  end
end

include("RobotBasedMagneticFieldStaticProtocol.jl")
#include("RobotBasedMagneticFieldSweepProtocol.jl")
#include("RobotBasedSystemMatrixProtocol.jl")