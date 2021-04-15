using Configurations
using ReusePatterns

"Option A"
@option struct Device
    deviceID::String
    deviceType::String
end

abstract type TestAbstract end

@option struct ConcreteDevice <: TestAbstract
    float::Float64
end

d = Dict{String, Any}(
    #"name" => "Test"
    #"int" => 1
    "float" => 0.33
);

option = from_dict(ConcreteDevice, d)