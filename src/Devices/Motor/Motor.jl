using Graphics: @mustimplement

export Motor, StepperMotor

abstract type Motor <: Device end
abstract type StepperMotor <: Motor end

export MotorDirection, MOTOR_FORWARD, MOTOR_BACKWARD, MOTOR_STILL
@enum MotorDirection begin
  MOTOR_FORWARD
  MOTOR_BACKWARD
  MOTOR_STILL
end

Base.close(motor::Motor) = nothing

export getMotors
getMotors(scanner::MPIScanner) = getDevices(scanner, Motor)

export getMotor
getMotor(scanner::MPIScanner) = getDevice(scanner, Motor)

export direction
@mustimplement direction(motor::Motor)

export emergencyBreak
@mustimplement emergencyBreak(motor::Motor)

export drive
@mustimplement drive(motor::Motor, direction::MotorDirection)

export driveSteps
@mustimplement driveSteps(motor::StepperMotor, numSteps::Integer, direction_::MotorDirection=MOTOR_FORWARD)

export stop
@mustimplement stop(motor::Motor, delay::typeof(1.0u"s") = 0u"s")

export progress
@mustimplement progress(motor::StepperMotor)

include("SimulatedMotor.jl")
include("TinkerforgeSilentStepper.jl")