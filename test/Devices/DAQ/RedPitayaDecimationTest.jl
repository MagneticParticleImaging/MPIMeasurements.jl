@testset "Red Pitaya decimation" begin
  check(decimation) = MPIMeasurements.checkRedPitayaDecimation(decimation, 7.8125e6u"Hz", 1.25e8u"Hz")
  for decimation in [8, 64, 8192]
    @test isnothing(check(decimation))
  end
  for decimation in [6, 9, 8194]
    @test_throws MPIMeasurements.ScannerConfigurationError check(decimation)
    @test_throws "has a value of $decimation but has to be an even integer from 8 to 8192 for the Red Pitaya" check(decimation)
  end
end
