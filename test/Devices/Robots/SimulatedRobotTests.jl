r_params = SimulatedRobotParams()
rob = SimulatedRobot("simRob", r_params)
@test state(rob)==:INIT
@test getPosition(rob)==[0,0,0]u"mm"
@test dof(rob)==3

@test namedPositions(rob)["origin"]==[0,0,0]u"mm"
@test collect(keys(namedPositions(rob))) == ["origin"]

setup(rob)
@test state(rob)==:DISABLED
@test_throws RobotStateError moveAbs(rob, [1,1,1]u"mm")
@test_throws RobotStateError setup(rob)

@test !isReferenced(rob)
enable(rob)
@test_throws RobotReferenceError moveAbs(rob, [1,1,1]u"mm")
@test_throws RobotReferenceError gotoPos(rob, "origin")
@test_throws RobotAxisRangeError moveRel(rob, [1,0,0]u"m") # out of range for axis 1
moveRel(rob, [10,0,0]u"mm")
doReferenceDrive(rob)
@test isReferenced(rob)
moveAbs(rob, [1,1,1]u"mm")
teachPos(rob, "pos1")
@test issetequal(keys(namedPositions(rob)), ["origin", "pos1"])

moveAbs(rob, 2u"mm",2u"mm",2u"mm")
teachPos(rob, "pos2")
gotoPos(rob, "pos1")
@test getPosition(rob) == [1,1,1]u"mm"

moveAbs(rob, [1,1,1]u"mm", 10u"mm/s")
@test_throws RobotDOFError moveAbs(rob, [1,1]u"mm")
reset(rob)
@test state(rob)==:INIT