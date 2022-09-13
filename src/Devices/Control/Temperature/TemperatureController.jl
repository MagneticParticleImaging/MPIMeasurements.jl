export TemperatureController
abstract type TemperatureController <: Device end

@enum TemperatureControlMode TEMP_THRESHOLD TEMP_PWM

include("ArduinoTemperatureController.jl")

Base.close(t::TemperatureController) = nothing

export getTemperatureControllers
getTemperatureControllers(scanner::MPIScanner) = getDevices(scanner, TemperatureController)

export getTemperatureController
getTemperatureController(scanner::MPIScanner) = getDevice(scanner, TemperatureController)

# "Sensor" Methods
export numChannels
@mustimplement numChannels(controller::TemperatureController)
export getTemperatures
@mustimplement getTemperatures(controller::TemperatureController)
export getTemperature
@mustimplement getTemperature(controller::TemperatureController, channel::Int)
export getChannelNames
@mustimplement getChannelNames(controller::TemperatureController)
export getChannelGroups
@mustimplement getChannelGroups(controller::TemperatureController)

# Control Methods
export enableControl
@mustimplement enableControl(controller::TemperatureController)

export disableControl
@mustimplement disableControl(controller::TemperatureController)