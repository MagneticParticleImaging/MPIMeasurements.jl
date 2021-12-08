function deviceTest(device::Device)
  @testset "$(string(typeof(device)))" begin
    # NOP
  end
end

include("Amplifier/AmplifierTests.jl")
#include("DAQ/DAQTests.jl")
#include("GaussMeter/GaussMeterTests.jl")
#include("Virtual/VirtualDeviceTests.jl")
#include("Robots/RobotTests.jl")

@testset "Devices" begin
  mpiScanner = MPIScanner(testScanner)
  for device in getDevices(mpiScanner, Device)
    deviceTest(device)
  end
end