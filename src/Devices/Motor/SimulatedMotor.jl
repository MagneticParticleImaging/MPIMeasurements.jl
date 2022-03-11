export SimulatedMotorParams, SimulatedMotor

Base.@kwdef struct SimulatedMotorParams <: DeviceParams
  
end
SimulatedMotorParams(dict::Dict) = params_from_dict(SimulatedMotorParams, dict)

Base.@kwdef mutable struct SimulatedMotor <: Motor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedMotorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  direction::MotorDirection = MOTOR_FORWARD
  speed::typeof(1.0u"1/s") = 1.0u"1/s"
end

function _init(motor::SimulatedMotor)
  # NOP
end

neededDependencies(::SimulatedMotor) = []
optionalDependencies(::SimulatedMotor) = []
Base.close(motor::SimulatedMotor) = nothing

