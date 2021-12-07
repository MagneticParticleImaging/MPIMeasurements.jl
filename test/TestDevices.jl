@enum TestEnum begin
  FOO
  BAR
end

for enum in [:TestEnum]
  @eval begin
    T = $enum
    function Base.convert(::Type{T}, x::String)
      try 
        return stringToEnum(x, T)
      catch ex
        throw(ScannerConfigurationError(ex.msg))
      end
    end
  end
end

Base.@kwdef mutable struct TestDeviceParams <: DeviceParams
  stringValue::String = "default"
  stringArray::Vector{String} = []

  enumValue::TestEnum = FOO
  enumArray::Vector{TestEnum} = []

  unitValue::typeof(1.0u"V") = 0u"V"
  unitArray::Vector{typeof(1.0u"V")} = []

  primitiveValue::Integer = 0
  primitveArray::Vector{Integer} = 0

  arrayArray::Vector{Vector{Bool}}
end

TestDeviceParams(dict::Dict) = params_from_dict(TestDeviceParams, dict)

# Basic Test Device
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

  initRan::Bool = false
end

init(dev::TestDevice) = dev.initRan = true
neededDependencies(dev::TestDevice) = []
optionalDependencies(dev::TestDevice) = []

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

  initRan::Bool = false
end

init(dev::TestMissingIDDevice) = dev.initRan = true
neededDependencies(dev::TestMissingIDDevice) = []
optionalDependencies(dev::TestMissingIDDevice) = []

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

  initRan::Bool = false
end

init(dev::TestMissingParamsDevice) = dev.initRan = true
neededDependencies(dev::TestMissingParamsDevice) = []
optionalDependencies(dev::TestMissingParamsDevice) = []

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

  initRan::Bool = false
end

init(dev::TestMissingOptionalDevice) = dev.initRan = true
neededDependencies(dev::TestMissingOptionalDevice) = []
optionalDependencies(dev::TestMissingOptionalDevice) = []

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

  initRan::Bool = false
end

init(dev::TestMissingPresentDevice) = dev.initRan = true
neededDependencies(dev::TestMissingPresentDevice) = []
optionalDependencies(dev::TestMissingPresentDevice) = []

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

  initRan::Bool = false
end

init(dev::TestMissingDependencyDevice) = dev.initRan = true
neededDependencies(dev::TestMissingDependencyDevice) = []
optionalDependencies(dev::TestMissingDependencyDevice) = []