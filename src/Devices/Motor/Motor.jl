using Graphics: @mustimplement

export Motor, StepperMotor, MotorDirection

abstract type Motor <: Device 
abstract type StepperMotor <: Motor

@enum MotorDirection begin
  MOTOR_FORWARD
  MOTOR_BACKWARD
  MOTOR_STILL
end

Base.close(motor::Motor) = nothing

@mustimplement direction(motor::Motor)
@mustimplement direction(motor::Motor, dir::MotorDirection)


getMotors(scanner::MPIScanner) = getDevices(scanner, Motor)
function getMotor(scanner::MPIScanner)
  motors = getMotors(scanner)
  if length(motors) > 1
    error("The scanner has more than one motor device. Therefore, a single motor cannot be retrieved unambiguously.")
  else
    return motors[1]
  end
end

"""
Returns x,y, and z values and applies a coordinate transformation
"""
function getXYZValues(gauss::GaussMeter)
  values = [getXValue(gauss), getYValue(gauss), getZValue(gauss)]
  return gauss.params.coordinateTransformation*values
end

include("SimulatedMotor.jl")
#include("TinkerforgeSilentStepper.jl")