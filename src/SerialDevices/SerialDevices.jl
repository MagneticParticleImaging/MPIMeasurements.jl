using LibSerialPort

include("SerialDevice.jl")
include("ServerDevice.jl")
# API for Gaussmeter
include("GaussMeterLowLevel.jl")
include("GaussMeterHighLevel.jl")
# API for Robots
include("HeadRobotLowLevel.jl")
include("BrukerRobotLowLevel.jl")
include("RobotMidLevel.jl")
include("RobotHighLevel.jl")
