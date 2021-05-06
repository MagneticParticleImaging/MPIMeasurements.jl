

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  
end

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  deviceID::String
  params::SequenceControllerParams
end

function setupSequence()

end