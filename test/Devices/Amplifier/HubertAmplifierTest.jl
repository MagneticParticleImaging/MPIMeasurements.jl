function deviceTest(device::HubertAmplifier)
    @testset "$(string(typeof(device)))" begin
        if ask_dialog("You are trying to start the Hubert amplifier hardware test. Please ensure that the amp is turned on and a load is connected. Please continue only if the robot is safe to move!", "Cancel", "Start test")
            @error "Hubert amp test has not been implemented yet!"
            @test_broken 0
        
            @test ask_dialog("Did everything seem normal?")
        else
            @test_broken 0
        end        
      end
end

@testset "Hubert amplifier without hardware" begin
  H = MPIMeasurements

  @testset "status byte" begin
    # bit 0 ready, 1 overload, 2 overtemperature, 4 interlock, 5-6 supply (A1110E), 7 on
    st = H.HubertStatus(0b1000_0001, H.A1110QE)
    @test st.ready && st.on && !st.overload && !st.overtemperature && !st.interlockActive
    @test ismissing(st.supplyVoltage)
    @test H.HubertStatus(0b0001_0110, H.A1110QE).overload
    @test !H.HubertStatus(0b0001_0110, H.A1110QE).on
    @test H.HubertStatus(0b0000_0000, H.A1110E).supplyVoltage == AMP_LOW_POWER_SUPPLY
    @test H.HubertStatus(0b0010_0000, H.A1110E).supplyVoltage == AMP_MID_POWER_SUPPLY
    @test H.HubertStatus(0b1110_0000, H.A1110E).supplyVoltage == AMP_HIGH_POWER_SUPPLY
    @test_throws "invalid power supply value 2" H.HubertStatus(0b0100_0000, H.A1110E)
    @test_throws "0x40" H.HubertStatus(0b0100_0000, H.A1110E)
    # The supply bits are not decoded for the A1110QE
    @test ismissing(H.HubertStatus(0b0100_0000, H.A1110QE).supplyVoltage)
    @test H._hubertIsOn(0x80)
    @test !H._hubertIsOn(0x7f)
  end

  @testset "model" begin
    @test H._parseHubertModel("P111MAIN", "amp") == H.A1110E
    @test H._parseHubertModel("P111MAINQE", "amp") == H.A1110QE
    @test_throws "`amp` did not respond" H._parseHubertModel("", "amp")
    @test_throws "unknown model \"XYZ\"" H._parseHubertModel("XYZ", "amp")
    params = HubertAmplifierPortParams(channelID="tx", port="COM99", baudrate=9600)
    amp = HubertAmplifier(deviceID="hubert", params=params, dependencies=Dict{String, Union{Device, Missing}}())
    @test_throws "has not been initialized" H._hubertModel(amp)
    amp.model = H.A1110QE
    @test H._hubertModel(amp) == H.A1110QE
  end

  @testset "acknowledgement" begin
    @test isnothing(H._checkHubertAck("amp", UInt8[0x03, 0x35, 0x01], UInt8[0x01], UInt8[0x01]))
    @test_throws "Expected the acknowledgement UInt8[0x01], received UInt8[0x00]" H._checkHubertAck("amp", UInt8[0x03, 0x35, 0x01], UInt8[0x01], UInt8[0x00])
  end

  @testset "ID command" begin
    cmd = H._hubertIdCommand("abc")
    @test length(cmd) == 130
    @test cmd[1:5] == UInt8[0x82, 0x52, UInt8('a'), UInt8('b'), UInt8('c')]
    @test all(iszero, cmd[6:end])
    # Non-ASCII characters take more than one byte
    cmd = H._hubertIdCommand("µ")
    @test length(cmd) == 130
    @test cmd[3:4] == codeunits("µ")
    @test length(H._hubertIdCommand("x"^128)) == 130
    @test_throws "at most 128 bytes, got 129" H._hubertIdCommand("x"^129)
    @test_throws "at most 128 bytes, got 130" H._hubertIdCommand("µ"^65)
  end

  @test H._hubertTemperature(0x2a) === 42.0u"°C"

  @testset "power supply mode from strings" begin
    @test convert(AmplifierPowerSupplyMode, "low voltage") == AMP_LOW_POWER_SUPPLY
    @test convert(AmplifierPowerSupplyMode, "MID") == AMP_MID_POWER_SUPPLY
    @test convert(AmplifierPowerSupplyMode, "high") == AMP_HIGH_POWER_SUPPLY
    @test_throws "Please use a value containing `low`, `mid` or `high`" convert(AmplifierPowerSupplyMode, "auto")
  end
end
