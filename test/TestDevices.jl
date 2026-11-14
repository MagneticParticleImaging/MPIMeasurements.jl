@enum TestEnum begin
  FOO
  BAR
end

for enum in [:TestEnum]
  @eval begin
    T = $enum
    function Base.convert(::Type{T}, x::String)
      try 
        return MPIMeasurements.stringToEnum(x, T)
      catch ex
        throw(ScannerConfigurationError(ex.msg))
      end
    end
  end
end

# Basic Test Devices
Base.@kwdef mutable struct TestDeviceParams <: DeviceParams
  stringValue::String = "default"
  stringArray::Vector{String} = []

  enumValue::TestEnum = FOO
  enumArray::Vector{TestEnum} = []

  unitValue::typeof(1.0u"V") = 0u"V"
  unitArray::Vector{typeof(1.0u"V")} = []

  primitiveValue::Integer = 0
  primitveArray::Vector{Integer} = []

  arrayArray::Vector{Vector{typeof(1.0u"mm")}} = []
end

TestDeviceParams(dict::Dict) = params_from_dict(TestDeviceParams, dict)

Base.@kwdef mutable struct TestDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

function MPIMeasurements._init(dev::TestDevice)
  dev.initRan = true
end
MPIMeasurements.neededDependencies(dev::TestDevice) = []
MPIMeasurements.optionalDependencies(dev::TestDevice) = []

Base.@kwdef mutable struct TestDependencyDeviceParams <: DeviceParams
  # NOP
end

TestDependencyDeviceParams(dict::Dict) = params_from_dict(TestDependencyDeviceParams, dict)

Base.@kwdef mutable struct TestDependencyDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDependencyDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

function MPIMeasurements._init(dev::TestDependencyDevice)
  dev.initRan = true
end
MPIMeasurements.neededDependencies(dev::TestDependencyDevice) = [TestDevice]
MPIMeasurements.optionalDependencies(dev::TestDependencyDevice) = []

Base.@kwdef mutable struct TestDeviceBParams <: DeviceParams
  # NOP
end

TestDeviceBParams(dict::Dict) = params_from_dict(TestDeviceBParams, dict)

Base.@kwdef mutable struct TestDeviceB <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceBParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

function MPIMeasurements._init(dev::TestDeviceB)
  dev.initRan = true
end
MPIMeasurements.neededDependencies(dev::TestDeviceB) = []
MPIMeasurements.optionalDependencies(dev::TestDeviceB) = []


# "Broken" Test Devices
Base.@kwdef mutable struct TestMissingIDDevice <: Device
  #"Unique device ID for this device as defined in the configuration."
  #deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

Base.@kwdef mutable struct TestMissingParamsDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  #"Parameter struct for this devices read from the configuration."
  #params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

Base.@kwdef mutable struct TestMissingOptionalDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  #"Flag if the device is optional."
	#optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

Base.@kwdef mutable struct TestMissingPresentDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  #"Flag if the device is present."
  #present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

Base.@kwdef mutable struct TestMissingDependencyDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  #"Vector of dependencies for this device."
  #dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

Base.@kwdef mutable struct TestMissingConfigFileDevice <: Device
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestDeviceParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  #"Path of the config used to create the device (either Scanner.toml or Device.toml)"
  #configFile::Union{String, Nothing} = nothing

  initRan::Bool = false
end

# Amplifier whose `turnOn` always fails
Base.@kwdef mutable struct TestFailingAmplifierParams <: DeviceParams
  channelID::String
end
TestFailingAmplifierParams(dict::Dict) = params_from_dict(TestFailingAmplifierParams, dict)

Base.@kwdef mutable struct TestFailingAmplifier <: Amplifier
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestFailingAmplifierParams
  "Flag if the device is optional."
  optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  turnOffCalls::Int = 0
end

MPIMeasurements._init(amp::TestFailingAmplifier) = nothing
MPIMeasurements.neededDependencies(amp::TestFailingAmplifier) = []
MPIMeasurements.optionalDependencies(amp::TestFailingAmplifier) = []
MPIMeasurements.turnOn(amp::TestFailingAmplifier) = error("$(deviceID(amp)) failed to turn on")
MPIMeasurements.turnOff(amp::TestFailingAmplifier) = amp.turnOffCalls += 1
MPIMeasurements.channelId(amp::TestFailingAmplifier) = amp.params.channelID

# Temperature controller that only records whether control is enabled
Base.@kwdef mutable struct TestTemperatureControllerParams <: DeviceParams
  # NOP
end
TestTemperatureControllerParams(dict::Dict) = params_from_dict(TestTemperatureControllerParams, dict)

Base.@kwdef mutable struct TestTemperatureController <: TemperatureController
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TestTemperatureControllerParams
  "Flag if the device is optional."
  optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  "Path of the config used to create the device (either Scanner.toml or Device.toml)"
  configFile::Union{String, Nothing} = nothing

  controlEnabled::Bool = true
end

MPIMeasurements._init(controller::TestTemperatureController) = nothing
MPIMeasurements.neededDependencies(controller::TestTemperatureController) = []
MPIMeasurements.optionalDependencies(controller::TestTemperatureController) = []
MPIMeasurements.enableControl(controller::TestTemperatureController) = controller.controlEnabled = true
MPIMeasurements.disableControl(controller::TestTemperatureController) = controller.controlEnabled = false
