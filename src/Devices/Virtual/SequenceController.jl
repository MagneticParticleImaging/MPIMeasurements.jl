

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  
end

SequenceControllerParams(dict::Dict) = from_dict(SequenceControllerParams, dict)

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  deviceID::String
  params::SequenceControllerParams
end

function setupSequence()

end