@testset "SimulatedRobot" begin
    params = SimulatedRobotParams()
    rob = SimulatedRobot("simRob",params)
    @test state(rob)==:INIT
    @test getPosition(rob)==[0,0,0]u"mm"
    @test dof(rob)==3

    setup(rob)
    @test state(rob)==:DISABLED
    @test_throws AssertionError moveAbs(rob,[1,1,1]u"mm")
    @test_throws AssertionError setup(rob)

    @test !isReferenced(rob)
    enable(rob)
    @test_throws AssertionError moveAbs(rob, [1,1,1]u"mm")
    @test_throws AssertionError moveRel(rob,[1,0,0]u"m") # out of range for axis 1
    doReferenceDrive(rob)
    @test isReferenced(rob)
    moveAbs(rob, [1,1,1]u"mm")
    reset(rob)
    @test state(rob)==:INIT
end