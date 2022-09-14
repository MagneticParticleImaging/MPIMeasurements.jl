export RobotAxisRangeError, RobotDeviceError, RobotDOFError, RobotReferenceError, RobotStateError, RobotTeachError, RobotExplicitCoordinatesError, RobotTimeoutError, RobotError, RobotSafetyError

abstract type RobotException <: Exception end

struct RobotStateError <: RobotException
    robot::Robot
    state::Union{RobotState,Nothing}
end

struct RobotAxisRangeError <: RobotException
    robot::Robot
    pos::RobotCoords
end

struct RobotDOFError <: RobotException
    robot::Robot
    dof::Int
end

struct RobotReferenceError <: RobotException
    robot::Robot
end

struct RobotDeviceError <: RobotException
    robot::Robot
    exc::Exception
end

struct RobotTeachError <: RobotException
    robot::Robot
    pos_name::String
end

struct RobotExplicitCoordinatesError <: RobotException
    robot::Robot
end

struct RobotTimeoutError <: RobotException
    robot::Robot
    msg::String
end

struct RobotError <: RobotException
    robot::Robot
    msg::String
end

struct RobotSafetyError <: Exception
    robot::Robot
    pos::RobotCoords
end

function Base.showerror(io::IO, ex::RobotStateError)
    if ex.state === nothing
        print(io, "RobotStateError: robot '$(deviceID(ex.robot))' is in state $(state(ex.robot))")
    else    
        print(io, "RobotStateError: robot '$(deviceID(ex.robot))' has to be in state $(ex.state) to perform the desired action. It was in state $(state(ex.robot)) instead.")
    end
end

Base.showerror(io::IO, ex::RobotAxisRangeError) = (print(io, "RobotAxisRangeError: position ");
                                               show(IOContext(io, :typeinfo => typeof(ex.pos)), ex.pos);
                                               print(io, " (ScannerCoords: ");
                                               show(IOContext(io, :typeinfo => typeof(toScannerCoords(ex.robot, ex.pos))), toScannerCoords(ex.robot, ex.pos));
                                               print(io, ") is out of the axis range "); 
                                               show(IOContext(io, :typeinfo => typeof(axisRange(ex.robot))), axisRange(ex.robot));
                                               print(io, " of robot '$(deviceID(ex.robot))'"))

Base.showerror(io::IO, ex::RobotDOFError) = print(io, "RobotDOFError: coordinates included $(ex.dof) axes, but robot '$(deviceID(ex.robot))' has $(dof(ex.robot)) degrees-of-freedom")

Base.showerror(io::IO, ex::RobotReferenceError) = print(io, "RobotReferenceError: robot '$(deviceID(ex.robot))' has to be referenced to perform this action")

Base.showerror(io::IO, ex::RobotDeviceError) = (println(io, "RobotDeviceError: during the communication with robot '$(deviceID(ex.robot))' the following error occured:"); showerror(io, ex.exc))

function Base.showerror(io::IO, ex::RobotTeachError)
    if haskey(namedPositions(ex.robot), ex.pos_name)
        print(io, "RobotTeachError: the desired position name $(ex.pos_name) is already defined for robot '$(deviceID(ex.robot))', to override the current value pass override=true")   
    else
        print(io, "RobotTeachError: the desired position $(ex.pos_name) is not defined for robot '$(deviceID(ex.robot))', use one of $(keys(namedPositions(ex.robot)))")
    end
end

Base.showerror(io::IO, ex::RobotExplicitCoordinatesError) = print(io, "RobotExplicitCoordinatesError: robot '$(deviceID(ex.robot))' has defined a coordinate transform and therefore needs explicit declaration of the used coordinate system. Please pass RobotCoords(pos) or ScannerCoords(pos).")

Base.showerror(io::IO, ex::RobotTimeoutError) = print(io, "RobotTimeoutError: robot '$(deviceID(ex.robot))' had an error with the following message: `$(ex.msg)`.")

Base.showerror(io::IO, ex::RobotError) = print(io, "RobotError: robot '$(deviceID(ex.robot))' had an error with the following message: `$(ex.msg)`.")

Base.showerror(io::IO, ex::RobotSafetyError) = (print(io, "RobotSafetyError: position ");
                                                show(IOContext(io, :typeinfo => typeof(ex.pos)), ex.pos);
                                                print(io, " (ScannerCoords: ");
                                                show(IOContext(io, :typeinfo => typeof(toScannerCoords(ex.robot, ex.pos))), toScannerCoords(ex.robot, ex.pos));
                                                print(io, ") is not safe to move to!"); )