abstract type VirtualDevice <: Device end

include("ProtocolController.jl")
include("SequenceController.jl")
include("SimulationController.jl")