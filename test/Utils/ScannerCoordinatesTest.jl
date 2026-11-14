@testset "Scanner coordinates" begin
  # Identity system
  sys = ScannerCoordinateSystem(3)
  @test sys.axes == [1.0 0 0; 0 1 0; 0 0 1]
  @test sys.origin == zeros(3) .* u"mm"

  # Axes given as a string: row i holds the robot axis that becomes scanner axis i
  sys = ScannerCoordinateSystem("y,z,x", [1.0, 2.0, 3.0] .* u"mm")
  @test sys.axes == [0.0 1 0; 0 0 1; 1 0 0]
  @test ScannerCoordinateSystem("-x,y,-z", nothing).axes == [-1.0 0 0; 0 1 0; 0 0 -1]
  @test ScannerCoordinateSystem("X,Y", nothing).origin == zeros(2) .* u"mm"

  # Axes given as columns
  @test ScannerCoordinateSystem([[0.0, 1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]], nothing).axes == [0.0 1 0; 1 0 0; 0 0 1]
  @test ScannerCoordinateSystem(nothing, [1.0, 2.0] .* u"mm").axes == [1.0 0; 0 1]
  @test_throws AssertionError ScannerCoordinateSystem([1.0 0; 0 1], [1.0, 2.0, 3.0] .* u"mm")

  # Robot -> scanner: subtract the origin, then apply the axes
  robotPos = RobotCoords([11.0, 22.0, 33.0] .* u"mm")
  scannerPos = toScannerCoords(sys, robotPos)
  @test scannerPos isa ScannerCoords
  @test scannerPos.data ≈ [20.0, 30.0, 10.0] .* u"mm"
  @test toScannerCoords(sys, scannerPos) === scannerPos

  # ... and back
  back = MPIMeasurements.toDeviceCoords(sys, scannerPos, RobotCoords)
  @test back isa RobotCoords
  @test back.data ≈ robotPos.data

  # Coordinates behave like vectors
  @test scannerPos[1] ≈ 20.0u"mm"
  @test size(scannerPos) == (3,)

  # The system is treated as a scalar in broadcasting
  @test MPIMeasurements.tryuparse.(sys) === sys
end
