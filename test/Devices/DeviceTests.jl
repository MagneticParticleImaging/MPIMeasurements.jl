@testset "Devices" begin
  include("Amplifier/AmplifierTests.jl")
  include("DAQ/DAQTests.jl")
  include("GaussMeter/GaussMeterTests.jl")
  include("Virtual/VirtualDeviceTests.jl")
  include("Robots/RobotTests.jl")
end