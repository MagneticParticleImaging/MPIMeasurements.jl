@testset "Scanner Construction" begin
  # Mandatory fields missing from device struct
  @testset "Incomplete Device Struct" begin
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingID")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingDepdendencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingOptional")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingPresent")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingParams")
  end

  # Dependencies are checked correctly
  @testset "Incorrect Dependency" begin
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceMissingDependencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceWrongDependencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceUninitDependencies")
  end
end