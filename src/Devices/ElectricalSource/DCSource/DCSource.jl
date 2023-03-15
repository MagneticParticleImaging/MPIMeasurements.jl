export DCSource

abstract type DCSource <: ElectricalSource end

include("SimulatedDCSource.jl")

Base.close(t::DCSource) = nothing

export getDCSources
getDCSources(scanner::MPIScanner) = getDevices(scanner, DCSource)

export getDCSource
getDCSource(scanner::MPIScanner) = getDevice(scanner, DCSource)

export enable
@mustimplement enable(source::DCSource)

export disable
@mustimplement disable(source::DCSource)

export output
@mustimplement output(source::DCSource, value::typeof(1.0u"V"))


