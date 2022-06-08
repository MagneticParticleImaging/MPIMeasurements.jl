include("Exceptions.jl")
include("SerialDevices/SerialDevices.jl")
include("SCPI/SCPIInstruments.jl")
include("DictToStruct.jl")
include("BidirectionalChannel.jl")
include("ScannerCoordinates.jl")

function Base.wait(::Nothing)
 @debug "Wait was called with `nothing`."
 # NOP
end

# I only add this here until https://github.com/JuliaLang/julia/pull/42272 is decided.
Base.convert(::Type{IPAddr}, str::AbstractString) = parse(IPAddr, str)