

@option struct SequenceControllerParams <: DeviceParams
  
end

@quasiabstract mutable struct SequenceController <: VirtualDevice
  
  function DummyDAQ(deviceID::String, params::DummyDAQParams)
      return new(deviceID, params, nothing)
  end
end

function setupSequence()

end