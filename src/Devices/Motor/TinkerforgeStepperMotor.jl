
export TinkerforgeStepperMotor
abstract type TinkerforgeStepperMotor <: StepperMotor end

@enum TinkerforgeStepResolution begin
  STEP_RESOLUTION_1 = 8
  STEP_RESOLUTION_2 = 7
  STEP_RESOLUTION_4 = 6
  STEP_RESOLUTION_8 = 5
  STEP_RESOLUTION_16 = 4
  STEP_RESOLUTION_32 = 3
  STEP_RESOLUTION_64 = 2
  STEP_RESOLUTION_128 = 1
  STEP_RESOLUTION_256 = 0
end
  
function convert(::Type{TinkerforgeStepResolution}, x::Integer)
  if x == 1
    return STEP_RESOLUTION_1
  elseif x == 2
    return STEP_RESOLUTION_2
  elseif x == 4
    return STEP_RESOLUTION_4
  elseif x == 8
    return STEP_RESOLUTION_8
  elseif x == 16
    return STEP_RESOLUTION_16
  elseif x == 32
    return STEP_RESOLUTION_32
  elseif x == 64
    return STEP_RESOLUTION_64
  elseif x == 128
    return STEP_RESOLUTION_128
  elseif x == 256
    return STEP_RESOLUTION_256
  else
    throw(ScannerConfigurationError("The given step resolution `$x` for the Tinkerforge silent stepper brick is not valid. Please use a power of two value between 1 and 256."))
  end
end

export enable
@mustimplement enable(motor::TinkerforgeStepperMotor)

export disable
@mustimplement disable(motor::TinkerforgeStepperMotor)

# Note: This is commented out because I am not sure how to handle the callback. Using a global variable would only work with one device.
# function allDataCallback(current_velocity, current_position, remaining_step, stack_voltage, external_voltage,
#                     current_consumption)
#     if ssBrick.get_driver_status().stallguard_result > 300:
#         stallSum = stallSum + ssBrick.get_driver_status().stallguard_result
#         print("stallSum: "+str(stallSum))
#     if (stallSum > stallThreashold):
#         stopMotorInSec(0)

#         print("Motor is stalled, so it was stopped\n")
#         infoString = "The motor stopped at:\n\tcurrent velocity = \t" + str(
#             current_velocity) + " steps per second\n\tcurrent velocity = \t" + str(
#             sps2rpm(current_velocity, microStepResolution, 1)
#         ) + "in rpm\n\tcurrent position = \t" + str(
#             current_position) + " in no of steps:\n\tremaining steps = \t" + str(
#             remaining_step) + " in no of steps\n\tcurrent consumption = \t" + str(
#             current_consumption) + " in milli amperes."
#         print(infoString)
#         print(getMotorStatus())
#         stalledVelocity = current_velocity
#         stalledBool = True
#     if getMotorDirection() == "still":
#         stallSum = 0

motorCurrent(motor::TinkerforgeStepperMotor) = motor.params.motorCurrent
stepResolution(motor::TinkerforgeStepperMotor) = motor.params.stepResolution
microStepResolution(motor::TinkerforgeStepperMotor) = round(Int64, 256 / (2^stepResolution(motor)))
gearRatio(motor::TinkerforgeStepperMotor) = motor.params.drivenGearTeeth // motor.params.drivingGearTeeth
#allowedVoltageDrop(motor::TinkerforgeStepperMotor) = motor.params.allowedVoltageDrop
stallThreshold(motor::TinkerforgeStepperMotor) = motor.params.stallThreshold


# Function that calculates the velocity in steps per second to get x rpm at the motor
rpm2sps(motor::TinkerforgeStepperMotor, rpm::Real) = rpm * 200 / 60 * microStepResolution(motor) * gearRatio(motor)
sps2rpm(motor::TinkerforgeStepperMotor, sps::Real) = sps * 60 / 200 * 1 / microStepResolution(motor) * 1 / gearRatio(motor)

function direction(motor::TinkerforgeStepperMotor)
  if PyTinkerforge.get_current_velocity(motor.deviceInternal) > 0
    return MOTOR_FORWARD
  elseif PyTinkerforge.get_current_velocity(motor.deviceInternal) < 0
    return MOTOR_BACKWARD
  else
    return MOTOR_STILL
  end
end

function emergencyBreak(motor::TinkerforgeStepperMotor)
  PyTinkerforge.full_brake(motor.deviceInternal)
  disable(motor)
end

function driveSteps(motor::TinkerforgeStepperMotor, numSteps::Integer, direction_::MotorDirection=MOTOR_FORWARD)
  if direction_ == MOTOR_BACKWARD
    numSteps = -numSteps
  end

  # If the motor is not still: brake and drive afterwards
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  # Enable the motor if not done already
  if !isEnabled(motor)
    enable(motor)
  end
  @warn PyTinkerforge.is_enabled(motor.deviceInternal)

  # Set the numper of steps the motor should drive. The sign defines the direction.
  PyTinkerforge.set_steps(motor.deviceInternal, numSteps)
end

function drive(motor::TinkerforgeStepperMotor, direction::MotorDirection)
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  if !isEnabled(motor)
    enable(motor)
  end

  if direction(motor) == MOTOR_BACKWARD
    PyTinkerforge.drive_backward(motor.deviceInternal) # drives motor with set parameters till drive_forward or stop is called
  else
    PyTinkerforge.drive_forward(motor.deviceInternal) # drives motor with set parameters till drive_backward or stop is called
  end
end

# Try to reach velocity while decreasing the acceleration and increasing the velocity
# Commented out because with it CI failed
#=function driveToVelocity(motor::TinkerforgeStepperMotor, rpm::typeof(u"1/s"), direction::MotorDirection)
  global stallThreashold
  stallThreashold = 10000
  if not (getMotorDirection() == "still"):
    stopMotorInSec(0)
  if not (ssBrick.is_enabled()):
    ssBrick.enable()  # enable the motor if not done already
    vSPS = rpm2sps(rpm, microStepResolution, gearRatio)
  while round(sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio)) < rpm:
  newAcceleration = 1000
  setupMotorParameters(vSPS, newAcceleration, vSPS / 2, motorCurrent, stepResolution)

  if sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio) > 500:
  newAcceleration = 50
  elif sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio) > 400:
  newAcceleration = 100
  elif sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio) > 300:
  newAcceleration = 200
  elif sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio) > 200:
  newAcceleration = 500
  elif sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio) > 100:
  newAcceleration = 1000
  else:
  newAcceleration = 1

  if (direction == "backward"):
  ssBrick.drive_backward()  # drives motor with set parameters till drive_forward or stop is called
  else:
  ssBrick.drive_forward()  # drives motor with set parameters till drive_backward or stop is called
  time.sleep(0.1)
  print(sps2rpm(ssBrick.get_current_velocity(),microStepResolution,gearRatio))
  if getMotorDirection() == "still":
  break

  if (direction == "backward"):
  ssBrick.drive_backward()  # drives motor with set parameters till drive_forward or stop is called
  else:
  ssBrick.drive_forward()  # drives motor with set parameters till drive_backward or stop is called
  stallThreashold = 20000
end=#

function stop(motor::TinkerforgeStepperMotor, delay::typeof(1.0u"s") = 0u"s")
  sleep(ustrip(u"s", delay))  # Delay the stop maneuver
  stop(motor)  # Stop the motor with the deacceleration set in the motor parameters

  # Wait till the motor has actually stopped before disabling the driver
  sleep((PyTinkerforge.get_max_velocity(motor.deviceInternal) / PyTinkerforge.get_speed_ramping(motor.deviceInternal).deacceleration) + 0.5)  # steps per second / steps per second^2 = second
  disable(motor)
  
  # global stallSum
  # stallSum=0
end

function progress(motor::TinkerforgeStepperMotor)
  setSteps = PyTinkerforge.get_steps(motor.deviceInternal)
  remainingSteps = PyTinkerforge.get_remaining_steps(motor.deviceInternal)
  donePercentage = 100 * remainingSteps / setSteps
  return donePercentage
end

include("TinkerforgeSilentStepperBrick.jl")