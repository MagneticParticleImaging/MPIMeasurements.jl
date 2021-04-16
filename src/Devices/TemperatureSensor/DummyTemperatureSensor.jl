export DummyTemperatureSensor, DummyTemperatureSensorParams, numChannels, getTemperature

@option struct DummyTemperatureSensorParams <: DeviceParams
  
end

@quasiabstract mutable struct DummyTemperatureSensor <: TemperatureSensor

  function DummyTemperatureSensor(deviceID::String, params::DummyTemperatureSensorParams)
    return new(deviceID, params)
  end
end

numChannels(sensor::DummyTemperatureSensor) = 1
getTemperature(sensor::DummyTemperatureSensor)::Vector{typeof(1u"°C")} = [42u"°C"]
getTemperature(sensor::DummyTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"