export SimulatedStepperMotorParams, SimulatedStepperMotor

Base.@kwdef struct SimulatedStepperMotorParams <: DeviceParams
  
end
SimulatedStepperMotorParams(dict::Dict) = params_from_dict(SimulatedStepperMotorParams, dict)

Base.@kwdef mutable struct SimulatedStepperMotor <: Motor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedStepperMotorParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  stepSize::typeof(1.0u"rad") = 1.0u"°"
end

function _init(motor::SimulatedStepperMotor)
  # NOP
end

driveSteps(motor::SimulatedStepperMotor, numSteps::Integer, direction_::MotorDirection=MOTOR_FORWARD) = @debug "Driving $numSteps steps with a step size of $(uconvert(u"°", motor.stepSize))."

neededDependencies(::SimulatedStepperMotor) = []
optionalDependencies(::SimulatedStepperMotor) = []
Base.close(motor::SimulatedStepperMotor) = nothing

