export TinkerforgeSilentStepperBrickParams, TinkerforgeSilentStepperBrick

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

Base.@kwdef struct TinkerforgeSilentStepperBrickParams <: DeviceParams
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  uid::String
  motorCurrent::typeof(1.0u"A")
  stepResolution::TinkerforgeStepResolution = STEP_RESOLUTION_256
  drivenGearTeeth::Integer = 1
  drivingGearTeeth::Integer = 1
  acceleration::typeof(1.0u"s^-2") = 1000u"s^-2"
  deacceleration::typeof(1.0u"s^-2") = 1000u"s^-2"
  velocity::typeof(1.0u"s^-1") = 1000u"s^-1"
  #allowedVoltageDrop
  stallThreshold::Integer = 20000
end
TinkerforgeSilentStepperBrickParams(dict::Dict) = params_from_dict(TinkerforgeSilentStepperBrickParams, dict)

Base.@kwdef mutable struct TinkerforgeSilentStepperBrick <: StepperMotor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TinkerforgeSilentStepperBrickParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  deviceInternal::Union{PyTinkerforge.BrickSilentStepper, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing

  stallSum = 0
end

function init(motor::TinkerforgeSilentStepperBrick)
  @debug "Initializing Tinkerforge silent stepper unit with ID `$(motor.deviceID)`."

  motor.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(motor.ipcon, motor.params.host, motor.params.port)
  motor.deviceInternal = PyTinkerforge.BrickSilentStepper(motor.params.uid, motor.ipcon)

  # connect the all_data callback to catch relevant motor information and stop on an error
  # motor.brick.set_all_data_period(100)  # /ms, return values every x milliseconds
  # motor.brick.register_callback(tinkerforge.brick_silent_stepper.BrickSilentStepper.CALLBACK_ALL_DATA, allDataCallback)

  # TODO: Move velocity to function of RPM
  PyTinkerforge.set_max_velocity(motor.deviceInternal, ustrip(u"s^-1", motor.params.velocity))  # /steps per s, max velocity in steps per second, depends on step_resolution
  PyTinkerforge.set_speed_ramping(motor.deviceInternal, ustrip(u"s^-2", motor.params.acceleration), ustrip(u"s^-2", motor.params.deacceleration))  # steps per s^2, acceleration and deacceleration of the motor, 8000 steps per s in 10 s equals 800 steps per s^2
  PyTinkerforge.set_motor_current(motor.deviceInternal, ustrip(u"mA", motor.params.motorCurrent))  # /mA, sets the current to drive the motor.
  PyTinkerforge.set_step_configuration(motor.deviceInternal, Int(motor.params.stepResolution), true)  # sets the defines stepResolution and activates Interpolation

  motor.present = true
  return
end

neededDependencies(::TinkerforgeSilentStepperBrick) = []
optionalDependencies(::TinkerforgeSilentStepperBrick) = []
Base.close(motor::TinkerforgeSilentStepperBrick) = PyTinkerforge.disconnect(motor.ipcon)

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

host(motor::TinkerforgeSilentStepperBrick) = motor.params.host
port(motor::TinkerforgeSilentStepperBrick) = motor.params.port
uid(motor::TinkerforgeSilentStepperBrick) = motor.params.uid
motorCurrent(motor::TinkerforgeSilentStepperBrick) = motor.params.motorCurrent
stepResolution(motor::TinkerforgeSilentStepperBrick) = motor.params.stepResolution
microStepResolution(motor::TinkerforgeSilentStepperBrick) = round(Int64, 256 / (2^stepResolution(motor)))
gearRatio(motor::TinkerforgeSilentStepperBrick) = motor.params.drivenGearTeeth // motor.params.drivingGearTeeth
allowedVoltageDrop(motor::TinkerforgeSilentStepperBrick) = motor.params.allowedVoltageDrop
stallThreshold(motor::TinkerforgeSilentStepperBrick) = motor.params.stallThreshold


# Function that calculates the velocity in steps per second to get x rpm at the motor
rpm2sps(motor::TinkerforgeSilentStepperBrick, rpm::Real) = rpm * 200 / 60 * microStepResolution(motor) * gearRatio(motor)
sps2rpm(motor::TinkerforgeSilentStepperBrick, sps::Real) = sps * 60 / 200 * 1 / microStepResolution(motor) * 1 / gearRatio(motor)

function direction(motor::TinkerforgeSilentStepperBrick)
  if PyTinkerforge.get_current_velocity(motor.deviceInternal) > 0
    return MOTOR_FORWARD
  elseif PyTinkerforge.get_current_velocity(motor.deviceInternal) < 0
    return MOTOR_BACKWARD
  else
    return MOTOR_STILL
  end
end

function emergencyBreak(motor::TinkerforgeSilentStepperBrick)
  PyTinkerforge.full_brake(motor.deviceInternal)
  PyTinkerforge.disable(motor.deviceInternal)
end

function driveSteps(motor::TinkerforgeSilentStepperBrick, numSteps::Integer, direction_::MotorDirection=MOTOR_FORWARD)
  if direction_ == MOTOR_BACKWARD
    numSteps = -numSteps
  end

  # If the motor is not still: brake and drive afterwards
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  # Enable the motor if not done already
  if !PyTinkerforge.is_enabled(motor.deviceInternal)
    PyTinkerforge.enable(motor.deviceInternal)
  end
  @warn PyTinkerforge.is_enabled(motor.deviceInternal)

  # Set the numper of steps the motor should drive. The sign defines the direction.
  PyTinkerforge.set_steps(motor.deviceInternal, numSteps)
end

function drive(motor::TinkerforgeSilentStepperBrick, direction::MotorDirection)
  if direction(motor) != MOTOR_STILL
    stop(motor, 0u"s")
  end

  if !is_enabled()
    PyTinkerforge.enable(motor.deviceInternal)
  end

  if direction(motor) == MOTOR_BACKWARD
    PyTinkerforge.drive_backward(motor.deviceInternal) # drives motor with set parameters till drive_forward or stop is called
  else
    PyTinkerforge.drive_forward(motor.deviceInternal) # drives motor with set parameters till drive_backward or stop is called
  end
end

# Try to reach velocity while decreasing the acceleration and increasing the velocity
# Commented out because with it CI failed
#=function driveToVelocity(motor::TinkerforgeSilentStepperBrick, rpm::typeof(u"1/s"), direction::MotorDirection)
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

function stop(motor::TinkerforgeSilentStepperBrick, delay::typeof(1.0u"s") = 0u"s")
  sleep(ustrip(u"s", delay))  # Delay the stop maneuver
  PyTinkerforge.stop(motor.deviceInternal)  # Stop the motor with the deacceleration set in the motor parameters

  # Wait till the motor has actually stopped before disabling the driver
  sleep((PyTinkerforge.get_max_velocity(motor.deviceInternal) / PyTinkerforge.get_speed_ramping(motor.deviceInternal).deacceleration) + 0.5)  # steps per second / steps per second^2 = second
  PyTinkerforge.disable(motor.deviceInternal)
  
  # global stallSum
  # stallSum=0
end

function progress(motor::TinkerforgeSilentStepperBrick)
  setSteps = PyTinkerforge.get_steps(motor.deviceInternal)
  remainingSteps = PyTinkerforge.get_remaining_steps(motor.deviceInternal)
  donePercentage = 100 * remainingSteps / setSteps
  return donePercentage
end