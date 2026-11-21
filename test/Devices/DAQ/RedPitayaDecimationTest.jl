@testset "Red Pitaya decimation" begin
  daq = unconnectedRedPitayaDAQ()

  for value in [8, 50, 64, 8192]
    decimation!(daq, value)
    @test decimation(daq) == value
  end

  decimation!(daq, 64)
  for value in [6, 9, 8194]
    @test_throws MPIMeasurements.ScannerConfigurationError decimation!(daq, value)
    @test_throws "The decimation has to be an even integer from 8 to 8192 for the Red Pitaya. Tried to set $value" decimation!(daq, value)
    @test decimation(daq) == 64
  end
end
