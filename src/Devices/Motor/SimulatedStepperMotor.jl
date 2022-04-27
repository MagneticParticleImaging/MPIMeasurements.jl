export SimulatedStepperMotorParams, SimulatedStepperMotor

Base.@kwdef struct SimulatedStepperMotorParams <: DeviceParams
  
end
SimulatedStepperMotorParams(dict::Dict) = params_from_dict(SimulatedStepperMotorParams, dict)

Base.@kwdef mutable struct SimulatedStepperMotor <: Motor
  @add_device_fields SimulatedStepperMotorParams

  stepSize::typeof(1.0u"rad") = 1.0u"°"
end

function _init(motor::SimulatedStepperMotor)
  # NOP
end

driveSteps(motor::SimulatedStepperMotor, numSteps::Integer, direction_::MotorDirection=MOTOR_FORWARD) = @debug "Driving $numSteps steps with a step size of $(uconvert(u"°", motor.stepSize))."

neededDependencies(::SimulatedStepperMotor) = []
optionalDependencies(::SimulatedStepperMotor) = []
Base.close(motor::SimulatedStepperMotor) = nothing

