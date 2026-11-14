@testset "Invalid configurations" begin
  fixture() = loadFixtureDict("MultiChannelSequence.toml")
  dfChannel(dict, chan) = dict["Fields"]["df"][chan]

  @testset "Channel and component types" begin
    # Unknown types should be reported with an ErrorException ("unknown channel type"),
    # but getConcreteType fails earlier when caching `nothing` in its Dict{String, Type}
    # (sequenceFromDict removes the `type` entries from the dict it is given, so every
    # call gets a fresh dict)
    unknownChannel() = (dict = fixture(); dfChannel(dict, "chanx")["type"] = "NoSuchChannel"; dict)
    @test_throws Exception sequenceFromDict(unknownChannel())
    @test_broken (try sequenceFromDict(unknownChannel()); false; catch e; e isa ErrorException; end)

    dict = fixture()
    delete!(dfChannel(dict, "chanx")["c1"], "type")
    @test_throws ErrorException sequenceFromDict(dict)

    unknownComponent() = (dict = fixture(); dfChannel(dict, "chanx")["c1"]["type"] = "NoSuchComponent"; dict)
    @test_throws Exception sequenceFromDict(unknownComponent())
    @test_broken (try sequenceFromDict(unknownComponent()); false; catch e; e isa ErrorException; end)
  end

  @testset "The input dict is consumed" begin
    # Loading removes the `type` entries from the given dict, so the same dict cannot be
    # loaded twice
    dict = fixture()
    seq = sequenceFromDict(dict)
    @test !haskey(dfChannel(dict, "chanx"), "type")
    @test_broken (try sequenceFromDict(dict) == seq; catch; false; end)
  end

  @testset "Control and decoupling flags" begin
    # A decoupled field must be controlled
    dict = fixture()
    dict["Fields"]["df"]["decouple"] = true
    dict["Fields"]["df"]["control"] = false
    @test_throws MPIMeasurements.SequenceConfigurationError sequenceFromDict(dict)

    # ... and is controlled implicitly if control is not given
    dict = fixture()
    dict["Fields"]["df"]["decouple"] = true
    delete!(dict["Fields"]["df"], "control")
    seq = sequenceFromDict(dict)
    @test MPIMeasurements.control(seq["df"])
    @test needsDecoupling(seq)
  end

  @testset "Units and values" begin
    dict = fixture()
    dfChannel(dict, "chanx")["offset"] = "1.0m"
    @test_throws "`offset` in `chanx`" sequenceFromDict(dict)
    @test_throws ErrorException sequenceFromDict(dict)

    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["offset"] = "1.0m"
    @test_throws "`offset` in `ffy`" sequenceFromDict(dict)

    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["amplitude"] = "1.0m"
    @test_throws "`amplitude` in `ffy`" sequenceFromDict(dict)

    dict = fixture()
    dict["Fields"]["ff"]["ffx"]["values"] = ["1.0m", "2.0m"]
    @test_throws "`values` in `ffx`" sequenceFromDict(dict)

    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["amplitude"] = ["1.0m"]
    @test_throws "The value of `amplitude` in `c1` has to be given as a current, a voltage or in tesla. You supplied the type" sequenceFromDict(dict)
    @test_throws ErrorException sequenceFromDict(dict)

    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["phase"] = ["sideways"]
    @test_throws ErrorException sequenceFromDict(dict)

    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["phase"] = "sideways"
    @test_throws ErrorException sequenceFromDict(dict)

    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["waveform"] = "sideways"
    @test_throws Exception sequenceFromDict(dict)

    # Integer values with a prefixed unit
    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["amplitude"] = ["10mT"]
    dfChannel(dict, "chanx")["offset"] = "1mT"
    dict["Fields"]["ff"]["ffx"]["values"] = ["1mT", "2mT", "3mT", "4mT"]
    dict["Fields"]["ff"]["ffy"]["amplitude"] = "1A"
    seq = sequenceFromDict(dict)
    @test amplitude(seq["df"]["chanx"]["c1"]) == 10u"mT"
    @test offset(seq["df"]["chanx"]) == 1u"mT"
    @test MPIMeasurements.values(seq["ff"]["ffx"]) == [1, 2, 3, 4] .* u"mT"
    @test seq["ff"]["ffy"].amplitude == 1.0u"A"
  end

  @testset "Phase keywords" begin
    # Periodic components: "sin" is the zero phase
    for (keyword, expected) in ["sine" => 0.0, "sin" => 0.0, "cosine" => π / 2, "cos" => π / 2,
                                "-sine" => 1.0π, "-sin" => 1.0π, "-cosine" => -π / 2, "-cos" => -π / 2]
      dict = fixture()
      dfChannel(dict, "chanx")["c1"]["phase"] = [keyword]
      @test phase(sequenceFromDict(dict)["df"]["chanx"]["c1"]) ≈ expected * u"rad"
    end
    # Continuous channels: "cos" is the zero phase
    for (keyword, expected) in ["cosine" => 0.0, "cos" => 0.0, "sine" => π / 2, "sin" => π / 2,
                                "-cosine" => 1.0π, "-cos" => 1.0π, "-sine" => -π / 2, "-sin" => -π / 2]
      dict = fixture()
      dict["Fields"]["ff"]["ffy"]["phase"] = keyword
      @test sequenceFromDict(dict)["ff"]["ffy"].phase ≈ expected * u"rad"
    end
    # Without a phase, components start at zero phase
    dict = fixture()
    delete!(dfChannel(dict, "chanx")["c1"], "phase")
    delete!(dict["Fields"]["ff"]["ffy"], "phase")
    seq = sequenceFromDict(dict)
    @test phase(seq["df"]["chanx"]["c1"]) == 0.0u"rad"
    @test seq["ff"]["ffy"].phase == 0.0u"rad"
  end

  @testset "Dividers" begin
    # Rational dividers can be given as an expression
    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["divider"] = "9600//2"
    @test divider(sequenceFromDict(dict)["df"]["chanx"]["c1"]) === 4800//1

    # The stepwise divider must be a multiple of the number of values
    dict = fixture()
    dict["Fields"]["ff"]["ffx"]["divider"] = 1459201
    @test_throws ErrorException sequenceFromDict(dict)

    # The continuous divider must be a multiple of dividerSteps
    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["dividerSteps"] = 364801
    @test_throws ErrorException sequenceFromDict(dict)

    # All acyclic channels must span the same number of periods ...
    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["divider"] = 729600
    @test_throws ErrorException acqNumPeriodsPerFrame(sequenceFromDict(dict))

    # ... and use the same number of periods per step
    dict = fixture()
    dict["Fields"]["ff"]["ffy"]["dividerSteps"] = 729600
    @test_throws ErrorException acqNumPeriodsPerPatch(sequenceFromDict(dict))

    # The sampling rate has to yield an integer number of samples per drive-field cycle
    # Decimation 512 does not divide the 364800 samples per cycle
    dict = fixture()
    dict["Acquisition"]["bandwidth"] = "122070.3125Hz" # 125 MHz / 1024
    @test_throws MPIMeasurements.ScannerConfigurationError rxNumSamplingPoints(sequenceFromDict(dict))
    # If the decimation itself is not an integer, building the error message fails with
    # an InexactError (Int(baseFrequency / samplingRate))
    dict = fixture()
    dict["Acquisition"]["bandwidth"] = "3.0MHz" # 6 MHz * 2.9184 ms = 17510.4
    seq = sequenceFromDict(dict)
    @test_throws Exception rxNumSamplingPoints(seq)
    @test_broken (try rxNumSamplingPoints(seq); false; catch e; e isa MPIMeasurements.ScannerConfigurationError; end)
  end

  @testset "Drive-field quirks" begin
    # Voltage amplitudes are stored as tesla with the value in millivolt
    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["amplitude"] = ["0.5V"]
    seq = sequenceFromDict(dict)
    strength = @test_logs (:warn, r"voltage") match_mode = :any dfStrength(seq)
    @test strength[1, 1, 1] ≈ 500.0u"T"

    # Components can have amplitudes and phases per period. dfStrength and dfPhase
    # should report all of them, but only see the first period.
    dict = fixture()
    for chan in ["chanx", "chany"], comp in keys(dfChannel(dict, chan))
      component = dfChannel(dict, chan)[comp]
      component isa Dict || continue
      component["amplitude"] = [component["amplitude"][1], "0.001T"]
      component["phase"] = ["0.0rad", "0.0rad"]
    end
    seq = sequenceFromDict(dict)
    @test amplitude(seq["df"]["chanx"]["c1"], period = 2) == 0.001u"T"
    @test_broken size(dfStrength(seq), 1) == 2
    @test_broken size(dfPhase(seq), 1) == 2
  end
end
