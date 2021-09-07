using MPIMeasurements
params = IselRobotParams(stepsPermm=160)
rob = IselRobot(deviceID="iselRob", params=params, dependencies=Dict{String, Union{Device, Missing}}())
ENV["JULIA_DEBUG"]="all"
setup(rob)
close(rob)
MPIMeasurements._getPosition(rob)
MPIMeasurements._setup(rob)
MPIMeasurements._doReferenceDrive(rob)
MPIMeasurements._moveAbs(rob, [40,0,0]u"mm", nothing)

moveAbs(rob, [5,0,0]u"mm")
moveRel(rob, [2,0,0]u"mm", 0.1u"mm/s")
doReferenceDrive(rob)
enable(rob)
disable(rob)
reset(rob)
setup(rob)
isReferenced(rob)
getPosition(rob)