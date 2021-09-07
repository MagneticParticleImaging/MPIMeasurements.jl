params = DummyRobotParams()
rob = DummyRobot(deviceID="dummy", params=params, dependencies=Dict{String, Union{Device, Missing}}())
@test state(rob)==:INIT
@test getPosition(rob)==[1.0,0,0]u"mm"
@test dof(rob)==3

setup(rob)
@test state(rob)==:DISABLED
@test_throws RobotStateError moveAbs(rob,[1,1,1]u"mm")
@test_throws RobotStateError setup(rob)

@test !isReferenced(rob)
enable(rob)
@test_throws RobotReferenceError moveAbs(rob, [1,1,1]u"mm")
moveRel(rob,[1,0,0]u"m")
doReferenceDrive(rob)
@test isReferenced(rob)
moveAbs(rob, [1,1,1]u"mm")
reset(rob)
@test state(rob)==:INIT

