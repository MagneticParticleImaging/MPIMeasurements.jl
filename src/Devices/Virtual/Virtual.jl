abstract type VirtualDevice <: Device end

include("SequenceController.jl")
include("SimulationController.jl")
include("MeasurementController.jl")