include("Exceptions.jl")
include("SerialDevices/SerialDevices.jl")
include("DictToStruct.jl")
include("Storage.jl")
include("BidirectionalChannel.jl")

function wait(::Nothing)
 # NOP
end 