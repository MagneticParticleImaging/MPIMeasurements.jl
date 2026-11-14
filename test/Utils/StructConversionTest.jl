@enum StructConversionTestMode MODE_A MODE_B

Base.@kwdef struct StructConversionTestInner
  label::String = "inner"
  length::typeof(1.0u"mm") = 2.5u"mm"
end

Base.@kwdef struct StructConversionTestParams
  name::String
  voltage::typeof(1.0u"V") = 1.0u"V"
  voltages::Vector{typeof(1.0u"V")} = [1.0u"V", 2.0u"V"]
  count::Int = 3
  mode::StructConversionTestMode = MODE_B
  inner::StructConversionTestInner = StructConversionTestInner()
end

@testset "Struct conversion" begin
  @testset "tryuparse" begin
    tryuparse = MPIMeasurements.tryuparse
    @test tryuparse("1.5mT") == 1.5u"mT"
    @test tryuparse("not a unit") == "not a unit"
    @test tryuparse(42) == 42 # non-strings are returned as they are
    @test tryuparse(["1.0V", "nope"]) == [1.0u"V", "nope"]
  end

  @testset "parsePossibleURange" begin
    parse = MPIMeasurements.parsePossibleURange
    @test parse("1.0mT") == 1.0u"mT"
    @test collect(parse("1.0mT:3.0mT")) == [1.0, 2.0, 3.0] .* u"mT" # step of one unit
    @test parse("0.0A:0.5A:1.5A") == [0.0, 0.5, 1.0, 1.5] .* u"A"
    @test parse("fill(2.0mT,3)") == fill(2.0u"mT", 3)
    @test parse("fill(true,2)") == [true, true]
    @test parse(["1.0V", "2.0V"]) == [1.0u"V", 2.0u"V"]
    @test_throws ArgumentError parse("1:2:3:4")

    chanDict = Dict{String, Any}("type" => "StepwiseElectricalChannel", "divider" => 12, "values" => "1.0mT:3.0mT")
    @test MPIMeasurements.values(MPIMeasurements.createFieldChannel("s", chanDict)) ≈ [1.0, 2.0, 3.0] .* u"mT"
  end

  @testset "parse_into_tf" begin
    # Files are only referenced, they are loaded later by the device
    @test MPIMeasurements.parse_into_tf("calibration.h5") == "calibration.h5"

    # A single value becomes a frequency-independent transfer function
    tf = MPIMeasurements.parse_into_tf("2.0V/T")
    @test tf.freq == [0.0, Inf]
    @test vec(tf.data) == ComplexF64[2.0, 2.0]
    @test tf.units == [u"V/T"]
    @test tf(10.0) == 2u"V/T"
    @test tf(1000000.0, 1) == 2u"V/T"

    # Frequency -> value pairs are sorted by frequency and converted to a common unit
    tf = MPIMeasurements.parse_into_tf(Dict("2000" => "2.0V/T", "1000" => "1000.0mV/T", "500" => "0.5V/T"))
    @test tf.freq == [500.0, 1000.0, 2000.0]
    @test uconvert.(u"V/T", vec(tf.data) .* tf.units[1]) ≈ ComplexF64[0.5, 1.0, 2.0] .* u"V/T"
  end

  @testset "dict_to_splatting and params_from_dict" begin
    dict = Dict{String, Any}("voltage" => "2.0V", "count" => 5,
      "same" => Dict{String, Any}("a" => "1.0V", "b" => "2.0V"),
      "mixed" => Dict{String, Any}("a" => "1.0V", "b" => "text"))
    splatting = MPIMeasurements.dict_to_splatting(dict)
    @test splatting[:voltage] == 2.0u"V"
    @test splatting[:count] == 5
    # Nested dicts with values of one type are specialized
    @test splatting[:same] isa Dict{String, typeof(1.0u"V")}
    @test splatting[:same]["b"] == 2.0u"V"
    @test splatting[:mixed] isa Dict{String, Any}
    @test splatting[:mixed]["b"] == "text"

    # With a type, string fields are not parsed as units ("1m" would be a length)
    splatting = MPIMeasurements.dict_to_splatting(StructConversionTestParams, Dict{String, Any}("name" => "1m", "voltage" => "3.0V"))
    @test splatting[:name] == "1m"
    @test splatting[:voltage] == 3.0u"V"

    params = MPIMeasurements.params_from_dict(StructConversionTestParams,
      Dict{String, Any}("name" => "test", "voltages" => ["3.0V", "4.0V"], "mode" => MODE_A))
    @test params.name == "test"
    @test params.voltages == [3.0u"V", 4.0u"V"]
    @test params.voltage == 1.0u"V" # default
    @test params.mode == MODE_A

    # Missing required fields are reported as configuration errors, other errors are rethrown
    @test_throws MPIMeasurements.ScannerConfigurationError MPIMeasurements.params_from_dict(StructConversionTestParams, Dict{String, Any}())
    @test_throws MethodError MPIMeasurements.params_from_dict(StructConversionTestParams, Dict{String, Any}("name" => "x", "count" => "many"))
  end

  @testset "stringToEnum" begin
    @test MPIMeasurements.stringToEnum("MODE_A", StructConversionTestMode) == MODE_A
    @test MPIMeasurements.stringToEnum("mode_b", StructConversionTestMode) == MODE_B
    @test_throws ArgumentError MPIMeasurements.stringToEnum("MODE_C", StructConversionTestMode)
  end

  @testset "toDict and toTOML" begin
    params = StructConversionTestParams(name = "test")
    dict = MPIMeasurements.toDict(params)
    @test dict["name"] == "test"
    @test dict["voltage"] == "1.0V" # quantities as strings without spaces
    @test dict["voltages"] == ["1.0V", "2.0V"]
    @test dict["count"] == 3
    @test dict["mode"] == "MODE_B" # enums by name
    @test dict["inner"] == Dict("label" => "inner", "length" => "2.5mm") # nested structs as dicts
    @test MPIMeasurements.toDictValue(5) == 5

    # Writing to a file and reading it back
    mktempdir() do dir
      file = joinpath(dir, "params.toml")
      MPIMeasurements.toTOML(file, params)
      parsed = MPIMeasurements.TOML.parsefile(file)
      @test parsed == dict
      parsed["mode"] = MPIMeasurements.stringToEnum(parsed["mode"], StructConversionTestMode)
      delete!(parsed, "inner")
      roundTrip = MPIMeasurements.params_from_dict(StructConversionTestParams, parsed)
      @test (roundTrip.name, roundTrip.voltage, roundTrip.voltages, roundTrip.count, roundTrip.mode) ==
        (params.name, params.voltage, params.voltages, params.count, params.mode)
    end
  end
end
