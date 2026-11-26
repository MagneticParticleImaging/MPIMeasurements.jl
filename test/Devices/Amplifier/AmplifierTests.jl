function deviceTest(amp::Amplifier)
  @testset "$(string(typeof(amp)))" begin
    @test state(amp) == false # default
    @test mode(amp) == AMP_VOLTAGE_MODE # Safe default
    @test powerSupplyMode(amp) == AMP_LOW_POWER_SUPPLY # Safe default
    @test matchingNetwork(amp) == 1 # default

    turnOn(amp)
    @test state(amp) == true

    turnOff(amp)
    @test state(amp) == false

    mode(amp, AMP_CURRENT_MODE)
    @test mode(amp) == AMP_CURRENT_MODE

    mode(amp, AMP_VOLTAGE_MODE)
    @test mode(amp) == AMP_VOLTAGE_MODE

    powerSupplyMode(amp, AMP_HIGH_POWER_SUPPLY)
    @test powerSupplyMode(amp) == AMP_HIGH_POWER_SUPPLY

    powerSupplyMode(amp, AMP_LOW_POWER_SUPPLY)
    @test powerSupplyMode(amp) == AMP_LOW_POWER_SUPPLY

    matchingNetwork(amp, 2)
    @test matchingNetwork(amp) == 2

    @test typeof(temperature(amp)) == typeof(1.0u"°C")

    toCurrentMode(amp)
    @test mode(amp) == AMP_CURRENT_MODE

    toVoltageMode(amp)
    @test mode(amp) == AMP_VOLTAGE_MODE

    toLowPowerSupplyMode(amp)
    @test powerSupplyMode(amp) == AMP_LOW_POWER_SUPPLY

    toHighPowerSupplyMode(amp)
    @test powerSupplyMode(amp) == AMP_HIGH_POWER_SUPPLY
  end
end

include("HubertAmplifierTest.jl")
