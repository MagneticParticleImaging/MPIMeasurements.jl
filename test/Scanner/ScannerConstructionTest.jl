@testset "Broken Scanner" begin
  @testset "Broken devices" begin

    # Mandatory fields missing from device struct
    @testset "Incomplete Device Struct" begin
      @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingID")
      @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingDepdendencies")
      @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingOptional")
      @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingPresent")
      @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingParams")
    end

  end
end