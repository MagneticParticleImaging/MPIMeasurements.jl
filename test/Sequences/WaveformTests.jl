@testset "Waveform" begin
  @testset "String conversion" begin
    @test toWaveform("sine") == WAVEFORM_SINE
    @test toWaveform("square") == WAVEFORM_SQUARE
    @test toWaveform("triangle") == WAVEFORM_TRIANGLE
    @test toWaveform("sawtooth_rising") == WAVEFORM_SAWTOOTH_RISING
    @test toWaveform("sawtooth") == WAVEFORM_SAWTOOTH_RISING # alias
    @test toWaveform("sawtooth_falling") == WAVEFORM_SAWTOOTH_FALLING
    @test toWaveform("custom") == WAVEFORM_ARBITRARY
    @test_throws KeyError toWaveform("bogus")

    # Every waveform maps to a name that maps back to the same waveform
    for w in instances(Waveform)
      @test toWaveform(fromWaveform(w)) == w
    end
    @test fromWaveform(WAVEFORM_SINE) == "sine"
    @test fromWaveform(WAVEFORM_ARBITRARY) == "custom"
    @test MPIMeasurements.toDictValue(WAVEFORM_TRIANGLE) == "triangle"

    # convert accepts the short names as well as the enum instance names (case-insensitive)
    @test convert(Waveform, "square") == WAVEFORM_SQUARE
    @test convert(Waveform, "WAVEFORM_TRIANGLE") == WAVEFORM_TRIANGLE
    @test convert(Waveform, "waveform_sawtooth_falling") == WAVEFORM_SAWTOOTH_FALLING
    @test_throws ArgumentError convert(Waveform, "bogus")
  end

  @testset "Values over one period" begin
    value = MPIMeasurements.value
    @test value(WAVEFORM_SINE, 0.0) ≈ 0.0 atol = 1e-12
    @test value(WAVEFORM_SINE, 0.25) ≈ 1.0
    @test value(WAVEFORM_SINE, 0.75) ≈ -1.0
    @test value(WAVEFORM_SINE, 1.25) ≈ 1.0 # the argument is taken modulo 1

    @test value(WAVEFORM_SQUARE, 0.1) == 1.0
    @test value(WAVEFORM_SQUARE, 0.6) == -1.0
    @test value(WAVEFORM_SQUARE, -0.4) == -1.0 # mod(-0.4, 1) == 0.6

    # Triangle: 0 -> 1 at a quarter period, back to -1 at three quarters, 0 at the end
    @test value(WAVEFORM_TRIANGLE, 0.0) == 0.0
    @test value(WAVEFORM_TRIANGLE, 0.125) ≈ 0.5
    @test value(WAVEFORM_TRIANGLE, 0.25) ≈ 1.0
    @test value(WAVEFORM_TRIANGLE, 0.5) ≈ 0.0 atol = 1e-12
    @test value(WAVEFORM_TRIANGLE, 0.75) ≈ -1.0
    @test value(WAVEFORM_TRIANGLE, 0.875) ≈ -0.5

    # Sawtooth and arbitrary waveforms have no closed-form value here
    @test_throws ErrorException value(WAVEFORM_SAWTOOTH_RISING, 0.1)
    @test_throws ErrorException value(WAVEFORM_ARBITRARY, 0.1)
  end
end
