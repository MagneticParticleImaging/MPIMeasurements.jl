using Gtk
params = IselRobotParams(stepsPermm=160, serial_port="COM3") #/dev/ttyUSB0
rob = IselRobot(deviceID="iselRob", params=params, dependencies=Dict{String, Union{Device, Missing}}())

if ask_dialog("You are trying to start the Isel robot hardware test. Please ensure that the robot is turned on, is able to reference itself and can move at least 50mm in all positive directions. Please continue only if the robot is safe to move!","Cancel","Start test")
    if isReferenced(rob)
        @test ask_dialog("The robot says it is already referenced. This usually means that the robot has not been powered off since the last reference drive. Is this the case?")
    end
        
    @test state(rob)==:INIT
    @test dof(rob)==3
    @test namedPositions(rob)["origin"]==[0,0,0]u"mm"
    @test collect(keys(namedPositions(rob))) == ["origin"]

    setup(rob)
    @test state(rob)==:DISABLED

    @test_throws RobotStateError moveAbs(rob, [1,1,1]u"mm")
    @test_throws RobotStateError setup(rob)

    enable(rob)
    @test state(rob)==:READY
    moveRel(rob, [10,10,10]u"mm")
    @test ask_dialog("Did the robot move 10mm in all positive directions?")
    moveRel(rob, [10,0,0]u"mm")
    @test ask_dialog("Did the robot move 10mm in the positive x direction?")
    moveRel(rob, [0,10,0]u"mm")
    @test ask_dialog("Did the robot move 10mm in the positive y direction?")
    moveRel(rob, [0,0,10]u"mm")
    @test ask_dialog("Did the robot move 10mm in the positive z direction?")

    @test_throws RobotAxisRangeError moveRel(rob,[10,10,10]u"m")
    @test_throws RobotDOFError moveRel(rob,[10u"mm",10u"mm"])
    @test_throws RobotDOFError moveAbs(rob,[10u"mm",10u"mm"])

    doReferenceDrive(rob)
    @test isReferenced(rob)

    moveAbs(rob, [20,0,0]u"mm")
    @test ask_dialog("Did the robot move to [20mm,0mm,0mm]?")
    @test getPosition(rob)==[20,0,0]u"mm"

    moveAbs(rob, [50,0,0]u"mm")
    @test ask_dialog("Did the robot move to [50mm,0mm,0mm]?")
    @test getPosition(rob)==[50,0,0]u"mm"

    teachNamedPosition(rob, "pos1")
    @test issetequal(keys(namedPositions(rob)), ["origin", "pos1"])
    @test namedPositions(rob)["pos1"] == [50,0,0]u"mm"
    @test_throws RobotTeachError teachNamedPosition(rob, "pos1")

    moveAbs(rob, [10,10,10]u"mm",20u"mm/s")
    @test ask_dialog("Did the robot move faster to [10mm,10mm,10mm]?")
    @test getPosition(rob)==[10,10,10]u"mm"

    gotoPos(rob, "pos1")
    @test ask_dialog("Did the robot move to [50mm,0mm,0mm]?")
    @test getPosition(rob)==[50,0,0]u"mm"

    gotoPos(rob, "origin", 20u"mm/s")
    @test ask_dialog("Did the robot move faster to [0mm,0mm,0mm]?")

    moveAbs(rob, [20,20,20]u"mm",20u"mm/s")
    @test ask_dialog("Did the robot move faster to [20mm,20mm,20mm]?")
    @test getPosition(rob)==[20,20,20]u"mm"

    reset(rob)
    @test state(rob)==:INIT
    setup(rob)
    enable(rob)

    #@test isReferenced(rob) #resetting of the igus robot should not lose the referencing

    disable(rob)
    @test ask_dialog("Did everything seem normal?")
else
    @test_broken 0
end