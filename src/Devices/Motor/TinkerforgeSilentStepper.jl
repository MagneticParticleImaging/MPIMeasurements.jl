export TinkerforgeSilentStepperParams, TinkerforgeSilentStepper

Base.@kwdef struct TinkerforgeSilentStepperParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
  motorCurrent::typeof(1.0u"A")
  stepResolution::Integer
  microStepResolution::Integer
  gearRatio::Rational = 1//1
  allowedVoltageDrop
  stallThreshold::Integer = 20000
end
TinkerforgeSilentStepperParams(dict::Dict) = params_from_dict(TinkerforgeSilentStepperParams, dict)

Base.@kwdef mutable struct TinkerforgeSilentStepper <: StepperMotor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SimulatedGaussMeterParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  brick = missing
  stallSum = 0
end

function _init(motor::TinkerforgeSilentStepper)
  tinkerforge = PyCall.pyimport("tinkerforge")
  ipConnection = tinkerforge.ip_connection.IPConnection()

  try
    ipConnection.connect(host, port)
  catch
    throw(ScannerConfigurationError("Could not establish a connection to the motor with the given parameters: "))
  end

  motor.brick = tinkerforge.brick_silent_stepper.BrickSilentStepper(uid(motor), ipConnection)

  # connect the all_data callback to catch relevant motor information and stop on an error
  # motor.brick.set_all_data_period(100)  # /ms, return values every x milliseconds
  # motor.brick.register_callback(tinkerforge.brick_silent_stepper.BrickSilentStepper.CALLBACK_ALL_DATA, allDataCallback)

  motor.brick.set_max_velocity(maxVelocity)  # /steps per s, max velocity in steps per second, depends on step_resolution
  motor.brick.set_speed_ramping(acceleration, deacceleration)  # steps per s^2, acceleration and deacceleration of the motor, 8000 steps per s in 10 s equals 800 steps per s^2
  motor.brick.set_motor_current(motorCurrent * 1000)  # /mA, sets the current to drive the motor.
  motor.brick.set_step_configuration(stepResolution, true)  # sets the defines stepResolution and activates Interpolation
end

checkDependencies(motor::TinkerforgeSilentStepper) = true

Base.close(motor::TinkerforgeSilentStepper) = nothing

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

host(motor::TinkerforgeSilentStepper) = motor.params.host
port(motor::TinkerforgeSilentStepper) = motor.params.port
uid(motor::TinkerforgeSilentStepper) = motor.params.uid
motorCurrent(motor::TinkerforgeSilentStepper) = motor.params.motorCurrent
stepResolution(motor::TinkerforgeSilentStepper) = motor.params.stepResolution
microStepResolution(motor::TinkerforgeSilentStepper) = motor.params.microStepResolution
gearRatio(motor::TinkerforgeSilentStepper) = motor.params.gearRatio
allowedVoltageDrop(motor::TinkerforgeSilentStepper) = motor.params.allowedVoltageDrop
stallThreshold(motor::TinkerforgeSilentStepper) = motor.params.stallThreshold


# Function that calculates the velocity in steps per second to get x rpm at the motor
rpm2sps(motor::TinkerforgeSilentStepper, rpm::Real) = rpm * 200 / 60 * microStepResolution(motor) * gearRatio(motor)
sps2rpm(motor::TinkerforgeSilentStepper, sps::Real) = sps * 60 / 200 * 1 / microStepResolution(motor) * 1 / gearRatio(motor)

function direction(motor::TinkerforgeSilentStepper)
  if motor.brick.get_current_velocity() > 0
    return MOTOR_FORWARD
  elseif motor.brick.get_current_velocity() < 0
    return MOTOR_BACKWARD
  else
    return MOTOR_STILL
  end
end

function emergencyBreak(motor::TinkerforgeSilentStepper)
  motor.brick.full_brake()
  motor.brick.disable()
end

function driveSteps(motor::TinkerforgeSilentStepper, numSteps::Integer, direction::MotorDirection)
  if direction == MOTOR_BACKWARD
    numSteps = -numSteps
  end

  # If the motor is not still: brake and drive afterwards
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  # Enable the motor if not done already
  if !motor.brick.is_enabled()
    motor.brick.enable()
  end

  # Set the numper of steps the motor should drive. The sign defines the direction.
  motor.brick.set_steps(numSteps)
end

function drive(motor::TinkerforgeSilentStepper, direction::MotorDirection)
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  if !motor.brick.is_enabled()
    motor.brick.enable()
  end

  if direction(motor) == MOTOR_BACKWARD
    motor.brick.drive_backward() # drives motor with set parameters till drive_forward or stop is called
  else
    motor.brick.drive_forward() # drives motor with set parameters till drive_backward or stop is called
  end
end

# Try to reach velocity while decreasing the acceleration and increasing the velocity
# Commented out because with it CI failed
#=function driveToVelocity(motor::TinkerforgeSilentStepper, rpm::typeof(u"1/s"), direction::MotorDirection)
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

function stop(motor::TinkerforgeSilentStepper, delay::typeof(1.0u"s") = 0u"s")
  sleep(ustrip(u"s", delay))  # Delay the stop maneuver
  motor.brick.stop()  # Stop the motor with the deacceleration set in the motor parameters

  # Wait till the motor has actually stopped before disabling the driver
  sleep((motor.brick.get_max_velocity() / motor.brick.get_speed_ramping().deacceleration) + 0.5)  # steps per second / steps per second^2 = second
  motor.brick.disable()
  
  # global stallSum
  # stallSum=0
end

function progress(motor::TinkerforgeSilentStepper)
  setSteps = motor.brick.get_steps()
  remainingSteps = motor.brick.get_remaining_steps()
  donePercentage = 100 * remainingSteps / setSteps
  return donePercentage
end