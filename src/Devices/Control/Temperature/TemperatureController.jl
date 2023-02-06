export TemperatureController, TemperatureControlMode
abstract type TemperatureController <: Device end

@enum TemperatureControlMode TEMP_THRESHOLD TEMP_PID TEMP_DUTYCYCLE

include("ArduinoTemperatureController.jl")

Base.close(t::TemperatureController) = nothing

export getTemperatureControllers
getTemperatureControllers(scanner::MPIScanner) = getDevices(scanner, TemperatureController)

export getTemperatureController
getTemperatureController(scanner::MPIScanner) = getDevice(scanner, TemperatureController)


# Control Methods
export enableControl
@mustimplement enableControl(controller::TemperatureController)

export disableControl
@mustimplement disableControl(controller::TemperatureController)