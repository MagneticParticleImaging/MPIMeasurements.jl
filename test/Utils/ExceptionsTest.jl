@testset "Exceptions" begin
  for T in [MPIMeasurements.ScannerConfigurationError, MPIMeasurements.ProtocolConfigurationError, MPIMeasurements.SequenceConfigurationError]
    ex = T("something is missing")
    @test ex isa MPIMeasurements.ConfigurationError
    @test ex isa Exception
    shown = sprint(show, ex)
    @test endswith(shown, "ConfigurationError: something is missing")
    @test occursin(string(nameof(T)), shown)
  end

  ex = MPIMeasurements.DeviceException("broken", nothing)
  @test ex isa MPIMeasurements.AbstractDeviceException
  @test endswith(sprint(show, ex), "DeviceException: broken")

  gauss = SimulatedGaussMeter(deviceID = "my_gauss", params = SimulatedGaussMeterParams(),
    dependencies = Dict{String, Union{Device, Missing}}())
  ex = MPIMeasurements.DeviceException("broken", gauss)
  @test endswith(sprint(show, ex), "DeviceException in device with ID `my_gauss`: broken")

  @test MPIMeasurements.CancelException() isa MPIMeasurements.ProtocolException
  @test MPIMeasurements.IllegalStateException("wrong state").message == "wrong state"
end
