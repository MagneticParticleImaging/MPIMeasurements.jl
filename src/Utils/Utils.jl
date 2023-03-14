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

# From https://github.com/JuliaGraphics/Graphics.jl/blob/6623e278162e75fbf86c15ad36f403c04bc47224/src/Graphics.jl#L388
macro mustimplement(sig)
  fname = sig.args[1]
  arg1 = sig.args[2]
  if isa(arg1,Expr)
      arg1 = arg1.args[1]
  end
  :($(esc(sig)) = error(typeof($(esc(arg1))),
                        " must implement ", $(Expr(:quote,fname))))
end