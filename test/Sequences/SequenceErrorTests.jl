@testset "Invalid configurations" begin
  fixture() = loadFixtureDict("MultiChannelSequence.toml")
  dfChannel(dict, chan) = dict["Fields"]["df"][chan]

  @testset "Channel and component types" begin
    unknownChannel() = (dict = fixture(); dfChannel(dict, "chanx")["type"] = "NoSuchChannel"; dict)
    @test_throws ErrorException sequenceFromDict(unknownChannel())
    @test_throws "Channel chanx has an unknown channel type `NoSuchChannel`" sequenceFromDict(unknownChannel())

    dict = fixture()
    delete!(dfChannel(dict, "chanx")["c1"], "type")
    @test_throws ErrorException sequenceFromDict(dict)

    unknownComponent() = (dict = fixture(); dfChannel(dict, "chanx")["c1"]["type"] = "NoSuchComponent"; dict)
    @test_throws ErrorException sequenceFromDict(unknownComponent())
    @test_throws "Component c1 has an unknown channel type `NoSuchComponent`" sequenceFromDict(unknownComponent())
  end

  @testset "The input dict is left unchanged" begin
    dict = fixture()
    seq = sequenceFromDict(dict)
    @test dict == fixture()
    @test sequenceFromDict(dict) == seq
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
    @test_throws "decimation (512)" rxNumSamplingPoints(sequenceFromDict(dict))
    # The decimation has to be an integer
    dict = fixture()
    dict["Acquisition"]["bandwidth"] = "3.0MHz" # 125 MHz / 6 MHz = 20.83
    seq = sequenceFromDict(dict)
    @test MPIMeasurements.rxDecimation(sequenceFromDict(fixture())) === 8
    @test_throws MPIMeasurements.ScannerConfigurationError MPIMeasurements.rxDecimation(seq)
    @test_throws MPIMeasurements.ScannerConfigurationError rxNumSamplingPoints(seq)
    @test_throws "The decimation has to be an integer, but the base frequency of 1.25e8 Hz and the rx sampling rate of 6.0e6 Hz (twice the rx bandwidth of 3.0e6 Hz) result in a decimation of 20.83" rxNumSamplingPoints(seq)
  end

  @testset "Drive-field quirks" begin
    # Voltage amplitudes are stored as tesla with the value in millivolt
    dict = fixture()
    dfChannel(dict, "chanx")["c1"]["amplitude"] = ["0.5V"]
    seq = sequenceFromDict(dict)
    strength = @test_logs (:warn, r"voltage") match_mode = :any dfStrength(seq)
    @test strength[1, 1, 1] ≈ 500.0u"T"

    # Components can have amplitudes and phases per period
    dict = fixture()
    for chan in ["chanx", "chany"], comp in keys(dfChannel(dict, chan))
      component = dfChannel(dict, chan)[comp]
      component isa Dict || continue
      component["amplitude"] = [component["amplitude"][1], "0.001T"]
      component["phase"] = ["0.0rad", "0.0rad"]
    end
    seq = sequenceFromDict(dict)
    @test amplitude(seq["df"]["chanx"]["c1"], period = 2) == 0.001u"T"
    @test size(dfStrength(seq)) == (2, 2, 2)
    @test size(dfPhase(seq)) == (2, 2, 2)
    @test dfStrength(seq)[:, 1, 1] == [0.01, 0.001] .* u"T"
    @test all(==(0.0u"rad"), dfPhase(seq))

    # All drive-field components must have the same number of periods
    dfChannel(dict, "chany")["c1"]["amplitude"] = ["12.0mT"]
    dfChannel(dict, "chany")["c1"]["phase"] = ["0.0rad"]
    seq = sequenceFromDict(dict)
    @test_throws MPIMeasurements.SequenceConfigurationError dfStrength(seq)
    @test_throws "Component c1 of channel chany defines 1 amplitudes instead of 2" dfStrength(seq)
    @test_throws "Component c1 of channel chany defines 1 phases instead of 2" dfPhase(seq)
  end
end
