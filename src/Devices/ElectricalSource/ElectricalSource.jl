
export ElectricalSource
abstract type ElectricalSource <: Device end

include("Amplifier/Amplifier.jl")
include("DCSource/DCSource.jl")