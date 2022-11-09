using Base: Integer

export RobotBasedProtocol, positions, postMoveWaitTime, numCooldowns, robotVelocity, switchBrakes, preMoveAction, postMoveAction

abstract type RobotBasedProtocol <: Protocol end
abstract type RobotBasedProtocolParams <: ProtocolParams end

# TODO which of these are currently necessary
#positions(protocol::RobotBasedProtocol)::Union{Positions, Missing} = protocol.params.positions
#postMoveWaitTime(protocol::RobotBasedProtocol)::typeof(1.0u"s") = protocol.params.postMoveWaitTime
#numCooldowns(protocol::RobotBasedProtocol)::Integer = protocol.params.numCooldowns
#robotVelocity(protocol::RobotBasedProtocol)::typeof(1.0u"m/s") = protocol.params.robotVelocity
#switchBrakes(protocol::RobotBasedProtocol)::Bool = protocol.params.switchBrakes

function _execute(protocol::RobotBasedProtocol)
  @info "Start $(typeof(protocol))"
  scanner_ = scanner(protocol)
  robot = getRobot(scanner_)
  if !isReferenced(robot)
    throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  end

  initMeasData(protocol)

  finished = false
  notifiedStop = false
  while !finished
    finished = performMovements(protocol)

    # Stopped 
    notifiedStop = false
    while protocol.stopped
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
      if !notifiedStop
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
  end

 
  put!(protocol.biChannel, FinishedNotificationEvent())
  while !protocol.finishAcknowledged
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    sleep(0.01)
  end
  @info "Protocol finished."
end

function performMovements(protocol::RobotBasedProtocol)
  @info "Enter robot movement loop"
  finished = false
  robot = getRobot(protocol.scanner)

  # TODO entering loop function
  while true
    @info "Curr Pos in performCalibrationInner $(calib.currPos)"
    handleEvents(protocol)
    
    if protocol.stopped
      enterPause(protocol)
      @info "Stop robot movement loop"
      finished = false
      break
    end

    pos = nextPosition(protocol)
    if !isnothing(pos)
      performMovement(protocol, robot, pos)
    else
      afterMovements(protocol)
      enable(robot)
      movePark(robot)
      disable(robot)
      finished = true
      break
    end
    
  end
    @info "Exit robot movement loop"
  return finished
end

performMovement(protocol::RobotBasedProtocol, robot::Robot, pos::RobotCoords) = performMovement(protocol, robot, toScannerCoords(robot, pos))
function performMovement(protocol::RobotBasedProtocol, robot::Robot, pos::ScannerCoords)
  preMovement(protocol)

  enable(robot)
  try
    @sync begin 
      moveRobot = @tspawnat protocol.scanner.generalParams.serialThreadID moveAbs(robot, pos)
      duringMovement(protocol, moveRobot)
    end
  catch ex 
    if ex isa CompositeException
      @error "CompositeException while preparing measurement:"
      for e in ex
        @error e
      end
    end
    rethrow(ex)
  end
  #diffTime = protocol.params.waitTime - timePreparing
  #if diffTime > 0.0
  #  sleep(diffTime)
  #end
  disable(robot)
  postMovement(protocol)
end



function preMovement(protocol::RobotBasedProtocol)
  # NOP
end

function duringMovement(protocol::RobotBasedProtocol, moving::Task)
  # NOP
end

function postMovement(protocol::RobotBasedProtocol)
  # NOP
end

function enterPause(protocol::RobotBasedProtocol)
  # NOP
end

function afterMovements(protocol::RobotBasedProtocol)
  # NOP
end

include("RobotBasedMagneticFieldStaticProtocol.jl")
#include("RobotBasedMagneticFieldSweepProtocol.jl")
include("RobotBasedSystemMatrixProtocol.jl")