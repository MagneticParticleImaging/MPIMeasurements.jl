include("Exceptions.jl")
include("DictToStruct.jl")
include("StructToToml.jl")
include("BidirectionalChannel.jl")
include("ScannerCoordinates.jl")
include("TracerDescription.jl")

function Base.wait(::Nothing)
 @debug "Wait was called with `nothing`."
 # NOP
end

# I only add this here until https://github.com/JuliaLang/julia/pull/42272 is decided.
Base.convert(::Type{IPAddr}, str::AbstractString) = parse(IPAddr, str)