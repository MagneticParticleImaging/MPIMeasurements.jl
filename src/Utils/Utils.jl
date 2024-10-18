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

# TODO: Remove this type piracy
Base.convert(::Type{ClusterTriggerSetup}, str::AbstractString) = stringToEnum(str, ClusterTriggerSetup)

# should be available in Unitful but isnt https://github.com/PainterQubits/Unitful.jl/issues/240
function timeFormat(t::Unitful.Time)
  v = ustrip(u"s",t)
  if v>3600  
    x = Int((v%3600)÷60)
    return "$(Int(v÷3600)):$(if x<10; "0" else "" end)$(x) h"
  elseif v>60
    x = round(v%60,digits=1)
    return "$(Int(v÷60)):$(if x<10; "0" else "" end)$(x) min"
  elseif v>0.5
    return "$(round(v,digits=2)) s"
  elseif v>0.5e-3
    return "$(round(v*1e3,digits=2)) ms"
  else
    return "$(round(v*1e6,digits=2)) µs"
  end
end 