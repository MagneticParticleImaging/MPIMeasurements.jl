@testset "Red Pitaya Tx voltage limits" begin
  channels = Dict{String, MPIMeasurements.DAQChannelParams}(
    "tx1" => MPIMeasurements.DAQTxChannelParams(channelIdx=1, limitPeak=1.0u"V"),
    "tx2" => MPIMeasurements.DAQTxChannelParams(channelIdx=2, limitPeak=0.5u"V"),
  )
  daq = unconnectedRedPitayaDAQ(channels)

  amps(x...) = Vector{Union{Float32, Nothing}}(collect(Float32, x))
  check(offsets, amplitudes, awg=nothing) = MPIMeasurements.checkTxLimits(daq, offsets, amplitudes, awg)

  # 0.2 + 0.5 + 0.2 = 0.9 < 1.0; negative values count with their magnitude
  @test isnothing(check(Dict("tx1" => -0.2f0), Dict("tx1" => amps(0.3, -0.2)), Dict("tx1" => Float32[0.1, -0.2])))
  @test isnothing(check(Dict("tx1" => 0.0f0), Dict("tx1" => amps(0.3, 0.2))))
  # A `nothing` amplitude contributes nothing to the check
  @test isnothing(check(Dict{String, Float32}(), Dict("tx1" => Union{Float32, Nothing}[0.9f0, nothing])))

  # Each part is below the limit, the sum is not
  @test_throws ArgumentError check(Dict("tx1" => 0.5f0), Dict("tx1" => amps(0.3)), Dict("tx1" => Float32[0.25]))
  @test_throws "channel `tx1`" check(Dict("tx1" => 0.5f0), Dict("tx1" => amps(0.3)), Dict("tx1" => Float32[0.25]))
  @test_throws "1.05" check(Dict("tx1" => 0.5f0), Dict("tx1" => amps(0.3)), Dict("tx1" => Float32[0.25]))
  @test_throws "limit of 1.0 V" check(Dict("tx1" => 0.5f0), Dict("tx1" => amps(0.3)), Dict("tx1" => Float32[0.25]))
  # Negative offset
  @test_throws "channel `tx1`" check(Dict("tx1" => -0.8f0), Dict("tx1" => amps(0.3)))
  @test_throws "channel `tx1`" check(Dict("tx1" => -1.5f0), Dict{String, Vector{Union{Float32, Nothing}}}())
  # Exactly at the limit is rejected
  @test_throws "channel `tx2`" check(Dict("tx2" => 0.5f0), Dict{String, Vector{Union{Float32, Nothing}}}())
  # Channels that only appear in the amplitudes or only in the AWG are checked
  @test_throws "channel `tx2`" check(Dict("tx1" => 0.0f0), Dict("tx2" => amps(0.3, 0.3)))
  @test_throws "channel `tx2`" check(Dict("tx1" => 0.0f0), Dict{String, Vector{Union{Float32, Nothing}}}(), Dict("tx2" => Float32[0.0, -0.6]))
  # Non-finite values
  @test_throws "not finite" check(Dict("tx1" => NaN32), Dict("tx1" => amps(0.1)))
  @test_throws "not finite" check(Dict("tx1" => 0.0f0), Dict("tx1" => amps(NaN)))
  @test_throws "not finite" check(Dict("tx1" => 0.0f0), Dict("tx1" => amps(0.1)), Dict("tx1" => Float32[0.0, Inf]))
  # Unknown channel
  @test_throws KeyError check(Dict("unknown" => 0.0f0), Dict{String, Vector{Union{Float32, Nothing}}}())

  # `setTxParams` checks before anything is sent; the device here has no connection, so any
  # attempt to send would fail with a different error.
  @test_throws "channel `tx1`" setTxParams(daq, Dict("tx1" => 0.5f0), Dict("tx1" => amps(0.3)), Dict("tx1" => amps(0.0)), Dict("tx1" => Float32[0.25]))
  @test_throws "channel `tx1`" setTxParams(daq, Dict("tx1" => -0.5u"V"), Dict("tx1" => [0.6u"V"]), Dict("tx1" => [0.0u"rad"]))
  @test_throws "channel `tx2`" setTxParams(daq, Dict("tx1" => 0.0u"V"), Dict("tx1" => [0.1u"V"]), Dict("tx1" => [0.0u"rad"]), Dict("tx2" => [0.0u"V", 0.7u"V"]))
end
