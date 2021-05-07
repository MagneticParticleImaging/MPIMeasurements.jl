params = IgusRobotParams()
rob = IgusRobot("igusRob",params)

@test state(rob)==:INIT
@test getPosition(rob)==[0]u"mm"
@test dof(rob)==1

setup(rob)
@test state(rob)==:DISABLED

@test_throws AssertionError moveAbs(rob, 1u"mm")
@test_throws AssertionError moveAbs(rob, [1]u"mm")
@test_throws AssertionError setup(rob)

@test !isReferenced(rob)
isReferenced(rob)
getPosition(rob)
enable(rob)
disable(rob)
@test state(rob)==:READY
@test_throws AssertionError moveAbs(rob, [1]u"mm")
moveRel(rob,[10]u"mm")
moveRel(rob,10u"mm")
@test_throws AssertionError moveRel(rob,10u"m")
@test doReferenceDrive(rob)
moveAbs(rob, [20]u"mm")
moveAbs(rob, 50u"mm")
moveAbs(rob, [10u"mm"],20u"mm/s")
moveAbs(rob, [50u"mm"],[20u"mm/s"])
reset(rob)
@test state(rob)==:INIT