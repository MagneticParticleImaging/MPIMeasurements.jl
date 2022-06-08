export TinkerforgeSilentStepperBrickletV2Params, TinkerforgeSilentStepperBrickletV2

Base.@kwdef struct TinkerforgeSilentStepperBrickletV2Params <: DeviceParams
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
TinkerforgeSilentStepperBrickletV2Params(dict::Dict) = params_from_dict(TinkerforgeSilentStepperBrickletV2Params, dict)

Base.@kwdef mutable struct TinkerforgeSilentStepperBrickletV2 <: TinkerforgeStepperMotor
  @add_device_fields TinkerforgeSilentStepperBrickletV2Params

  deviceInternal::Union{PyTinkerforge.BrickletSilentStepperV2, Missing} = missing
  ipcon::Union{PyTinkerforge.IPConnection, Missing} = missing

  stallSum = 0
end

function init(motor::TinkerforgeSilentStepperBrickletV2)
  @debug "Initializing Tinkerforge silent stepper unit with ID `$(motor.deviceID)`."

  motor.ipcon = PyTinkerforge.IPConnection()
  PyTinkerforge.connect(motor.ipcon, motor.params.host, motor.params.port)
  motor.deviceInternal = PyTinkerforge.BrickletSilentStepperV2(motor.params.uid, motor.ipcon)

  # connect the all_data callback to catch relevant motor information and stop on an error
  # motor.brick.set_all_data_period(100)  # /ms, return values every x milliseconds
  # motor.brick.register_callback(tinkerforge.brick_silent_stepper.BrickletSilentStepperV2.CALLBACK_ALL_DATA, allDataCallback)

  # TODO: Move velocity to function of RPM
  PyTinkerforge.set_max_velocity(motor.deviceInternal, ustrip(u"s^-1", motor.params.velocity))  # /steps per s, max velocity in steps per second, depends on step_resolution
  PyTinkerforge.set_speed_ramping(motor.deviceInternal, ustrip(u"s^-2", motor.params.acceleration), ustrip(u"s^-2", motor.params.deacceleration))  # steps per s^2, acceleration and deacceleration of the motor, 8000 steps per s in 10 s equals 800 steps per s^2
  PyTinkerforge.set_motor_current(motor.deviceInternal, ustrip(u"mA", motor.params.motorCurrent))  # /mA, sets the current to drive the motor.
  PyTinkerforge.set_step_configuration(motor.deviceInternal, Int(motor.params.stepResolution), true)  # sets the defines stepResolution and activates Interpolation

  motor.present = true
  return
end

neededDependencies(::TinkerforgeSilentStepperBrickletV2) = []
optionalDependencies(::TinkerforgeSilentStepperBrickletV2) = []
Base.close(motor::TinkerforgeSilentStepperBrickletV2) = PyTinkerforge.disconnect(motor.ipcon)
isTinkerforgeDevice(::TinkerforgeSilentStepperBrickletV2) = true

enable(motor::TinkerforgeSilentStepperBrickletV2) = PyTinkerforge.enable(motor.deviceInternal)
disable(motor::TinkerforgeSilentStepperBrickletV2) = PyTinkerforge.disable(motor.deviceInternal)
isEnabled(motor::TinkerforgeSilentStepperBrickletV2) = PyTinkerforge.is_enabled(motor.deviceInternal)
stop(motor::TinkerforgeSilentStepperBrickletV2) = PyTinkerforge.stop(motor.deviceInternal)
