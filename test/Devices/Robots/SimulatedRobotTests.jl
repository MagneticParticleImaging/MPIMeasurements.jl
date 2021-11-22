r_params = SimulatedRobotParams(coordinateSystem=RobotCoordinateSystem(axes="y,x,-z", origin=[0,0,50]u"mm"), movementOrder="zyx")
rob = SimulatedRobot(deviceID="simRob", params=r_params, dependencies=Dict{String, Union{Device, Missing}}())

@test state(rob)==:INIT
@test getPosition(rob)==[0,0,0]u"mm"
@test dof(rob)==3

@test namedPositions(rob)["origin"]==[0,0,0]u"mm"
@test collect(keys(namedPositions(rob))) == ["origin"]

setup(rob)
@test state(rob)==:DISABLED
@test_throws RobotStateError moveAbs(rob, RobotCoords([1,1,1]u"mm"))
@test_throws RobotExplicitCoordinatesError moveAbs(rob, [1,1,1]u"mm")
@test_throws RobotStateError setup(rob)

@test !isReferenced(rob)
enable(rob)
@test_throws RobotReferenceError moveAbs(rob, RobotCoords([1,1,1]u"mm"))
@test_throws RobotReferenceError gotoPos(rob, "origin")
@test_throws RobotAxisRangeError moveRel(rob, RobotCoords([1,0,0]u"m")) # out of range for axis 1
@test_throws RobotAxisRangeError moveRel(rob, RobotCoords([0,0,1]u"m")) # out of range for axis 3
@test_throws RobotAxisRangeError moveRel(rob, ScannerCoords([450,0,0]u"mm")) # out of range for axis 2

@test_logs (:warn, "Performing relative movement in unreferenced state, cannot validate coordinates! Please proceed carefully and perform only movements which are safe!") moveRel(rob, RobotCoords([10,0,0]u"mm"))

doReferenceDrive(rob)
@test isReferenced(rob)
moveAbs(rob, RobotCoords([1,1,1]u"mm"))
teachNamedPosition(rob, "pos1")
@test issetequal(keys(namedPositions(rob)), ["origin", "pos1"])

moveAbs(rob, RobotCoords([2u"mm",2u"mm",2u"mm"]))
teachNamedPosition(rob, "pos2")
gotoPos(rob, "pos1")
@test getPosition(rob) == [1,1,1]u"mm"

moveAbs(rob, RobotCoords([1,1,1]u"mm"), 10u"mm/s")
@test_throws RobotDOFError moveAbs(rob, RobotCoords([1,1]u"mm"))
reset(rob)
@test state(rob)==:INIT

setup(rob)
enable(rob)
moveAbs(rob, RobotCoords([0,0,0]u"mm"))
@test getPosition(rob) == [0,0,0]u"mm"
moveAbs(rob, ScannerCoords([0,0,0]u"mm"))
@test getPosition(rob) == scannerCoordOrigin(rob)
@test getPositionScannerCoords(rob) == [0,0,0]u"mm"

moveRel(rob, RobotCoords([1,0,0]u"mm"))
@test getPositionScannerCoords(rob) == scannerCoordAxes(rob)[1,:] * u"mm"

moveAbs(rob, ScannerCoords([0,0,0]u"mm"))
moveRel(rob, RobotCoords([0,0,1]u"mm"))
@test getPositionScannerCoords(rob) == scannerCoordAxes(rob)[3,:] * u"mm"

moveAbs(rob, ScannerCoords([0,0,0]u"mm"))
moveRel(rob, ScannerCoords([0,1,0]u"mm"))
@test getPosition(rob) == scannerCoordOrigin(rob) + scannerCoordAxes(rob)[:,2] * u"mm"