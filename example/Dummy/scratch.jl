# using Configurations
# using ReusePatterns

using MPIMeasurements



# "Option A"
# @option struct Device
#     deviceID::String
#     deviceType::String
# end

# abstract type TestAbstract end

# @option struct ConcreteDevice <: TestAbstract
#     float::Float64
# end

# d = Dict{String, Any}(
#     #"name" => "Test"
#     #"int" => 1
#     "float" => 0.33
# );

# option = from_dict(ConcreteDevice, d)

# abstract type DeviceParams end

# @option struct TestDeviceParams <: DeviceParams
#   testParam::String
# end

# @quasiabstract struct Device
#   deviceID::String
#   params::DeviceParams
# end

# @quasiabstract mutable struct TestDevice <: Device
#   testDeviceParam::String

#   function TestDevice(deviceID::String, params::TestDeviceParams)
#     return new(deviceID, params, "bla")
#   end
# end

# test = TestDevice("id", TestDeviceParams("testparam"))

# @info test.testDeviceParam
# test.testDeviceParam = "test"
# @info test.testDeviceParam


# function testDispatch(device::TestDevice)
#   @info device typeof(device) == TestDevice
# end

# testDispatch(test)

# function deepsubtypes(type::DataType)
#   subtypes_ = subtypes(type)
#   allSubtypes = subtypes_
#   for subtype in subtypes_
#     subsubtypes_ = deepsubtypes(subtype)
#     allSubtypes = vcat(allSubtypes, subsubtypes_)
#   end
#   return allSubtypes
# end

# knownDeviceTypes = deepsubtypes(Device)