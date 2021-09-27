include("Exceptions.jl")
include("SerialDevices/SerialDevices.jl")
include("SCPI/SCPIInstruments.jl")
include("DictToStruct.jl")
include("BidirectionalChannel.jl")

function wait(::Nothing)
 # NOP
end
