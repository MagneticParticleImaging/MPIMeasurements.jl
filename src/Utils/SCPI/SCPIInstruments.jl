export SCPIInstrument, SCPIInstrumentError, command, query

struct SCPIInstrumentError <: Exception
    msg::String
end

Base.showerror(io::IO, e::SCPIInstrumentError) = print(io, e.msg)

abstract type SCPIInstrument end

@mustimplement command(inst::SCPIInstrument, command_::String)
@mustimplement query(inst::SCPIInstrument, query_::String)

include("SerialSCPIInstrument.jl")
include("TCPSCPIInstrument.jl")