export SimulatedMotorParams, SimulatedMotor

Base.@kwdef struct SimulatedMotorParams <: DeviceParams

end
SimulatedMotorParams(dict::Dict) = params_from_dict(SimulatedMotorParams, dict)

Base.@kwdef mutable struct SimulatedMotor <: Motor
  @add_device_fields SimulatedMotorParams

  direction::MotorDirection = MOTOR_FORWARD
  speed::typeof(1.0u"1/s") = 1.0u"1/s"
end

function _init(motor::SimulatedMotor)
  # NOP
end

neededDependencies(::SimulatedMotor) = []
optionalDependencies(::SimulatedMotor) = []
Base.close(motor::SimulatedMotor) = nothing
