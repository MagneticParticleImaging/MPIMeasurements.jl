
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
microStepResolution(motor::TinkerforgeStepperMotor) = round(Int64, 256 / (2^Int(stepResolution(motor))))
gearRatio(motor::TinkerforgeStepperMotor) = motor.params.drivenGearTeeth // motor.params.drivingGearTeeth
nominalVoltage(motor::TinkerforgeStepperMotor) = motor.params.nominalVoltage
allowedVoltageDrop(motor::TinkerforgeStepperMotor) = motor.params.allowedVoltageDrop
stallThreshold(motor::TinkerforgeStepperMotor) = motor.params.stallThreshold

# Function that calculates the velocity in steps per second to get x rpm at the motor
rpm2sps(motor::TinkerforgeStepperMotor, rpm::Real) = rpm * 200 / 60 * microStepResolution(motor) * gearRatio(motor)
sps2rpm(motor::TinkerforgeStepperMotor, sps::Real) = sps * 60 / 200 * 1 / microStepResolution(motor) * 1 / gearRatio(motor)
rpm2Hz(rpm::T) where T <: Real = (rpm / 60)u"Hz"
Hz2rpm(velocity::T) where T <: Unitful.Frequency = ustrip(u"Hz", velocity)*60

function velocity!(motor::TinkerforgeStepperMotor, rpm::Real)
  velocitySPS = rpm2sps(motor, rpm)
  PyTinkerforge.set_max_velocity(motor.deviceInternal, velocitySPS)  # /steps per s, max velocity in steps per second, depends on step_resolution
  PyTinkerforge.set_speed_ramping(motor.deviceInternal, velocitySPS/20, velocitySPS / 10)  # steps per s^2, acceleration and deacceleration of the motor, 8000 steps per s in 10 s equals 800 steps per s^2
end
velocity!(motor::TinkerforgeStepperMotor, velocity::T) where T <: Unitful.Frequency = velocity!(motor, Hz2rpm(velocity))

velocity(motor::TinkerforgeStepperMotor) = rpm2Hz(sps2rpm(motor, PyTinkerforge.get_current_velocity(motor.deviceInternal)))

function waitForVelocity(motor::TinkerforgeStepperMotor, velocity_::T) where T <: Unitful.Frequency
  while true
    if round(typeof(1.0u"Hz"), velocity(motor)) == velocity_
      break
    end
    sleep(0.1)
  end
end

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

  # Set the numper of steps the motor should drive. The sign defines the direction.
  PyTinkerforge.set_steps(motor.deviceInternal, numSteps)
end

function driveDegree(motor::TinkerforgeStepperMotor, degree::Real,  direction::MotorDirection=MOTOR_FORWARD)
  numSteps = round(degree * gearRatio(motor) * 200 * microStepResolution(motor) / 360)
  driveSteps(motor, numSteps, direction)
end

function drive(motor::TinkerforgeStepperMotor, direction_::MotorDirection=MOTOR_FORWARD)
  if direction(motor) != MOTOR_STILL
    driveSteps(motor, 0u"s")
  end

  if !isEnabled(motor)
    enable(motor)
  end

  if direction_ == MOTOR_BACKWARD
    PyTinkerforge.drive_backward(motor.deviceInternal) # drives motor with set parameters till drive_forward or stop is called
  else
    PyTinkerforge.drive_forward(motor.deviceInternal) # drives motor with set parameters till drive_backward or stop is called
  end
end

function stop(motor::TinkerforgeStepperMotor, delay::T = 0u"s") where T <: Unitful.Time
  sleep(ustrip(u"s", delay))  # Delay the stop maneuver
  stop(motor)  # Stop the motor with the deacceleration set in the motor parameters

  # Wait till the motor has actually stopped before disabling the driver
  sleep((PyTinkerforge.get_max_velocity(motor.deviceInternal) / PyTinkerforge.get_speed_ramping(motor.deviceInternal)[2]) + 0.5)  # steps per second / steps per second^2 = second
  disable(motor)
end

function progress(motor::TinkerforgeStepperMotor)
  setSteps = PyTinkerforge.get_steps(motor.deviceInternal)
  remainingSteps = PyTinkerforge.get_remaining_steps(motor.deviceInternal)
  donePercentage = 100 * remainingSteps / setSteps
  return donePercentage
end

include("TinkerforgeSilentStepperBrick.jl")
include("TinkerforgeSilentStepperBricklet.jl")