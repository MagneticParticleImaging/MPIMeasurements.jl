MPIMeasurements.@mustimplement mustimplementTestFunction(x::Integer)

@testset "Miscellaneous utilities" begin
  @testset "timeFormat" begin
    timeFormat = MPIMeasurements.timeFormat
    @test timeFormat(7322.0u"s") == "2:02 h"
    @test timeFormat(125.0u"s") == "2:05.0 min"
    @test timeFormat(1.234u"s") == "1.23 s"
    @test timeFormat(12.3u"ms") == "12.3 ms"
    @test timeFormat(12.3u"µs") == "12.3 µs"
    @test timeFormat(2.0u"minute") == "2:00.0 min"
  end

  @testset "Conversions and no-ops" begin
    Sockets = MPIMeasurements.Sockets
    @test convert(Sockets.IPAddr, "192.168.1.100") == Sockets.IPv4("192.168.1.100")
    RP = MPIMeasurements.RedPitayaDAQServer
    @test convert(RP.ClusterTriggerSetup, "all_internal") == RP.ALL_INTERNAL
    @test isnothing(wait(nothing))
  end

  @testset "mustimplement" begin
    @test_throws ErrorException mustimplementTestFunction(1)
    @test occursin("must implement mustimplementTestFunction", (try mustimplementTestFunction(1); "" catch e; e.msg end))
  end

  @testset "Tracer description" begin
    MF = MPIMeasurements.MPIFiles
    tracer = MPIMeasurements.Tracer(name = "Perimag", solute = "Fe", vendor = "Micromod", batch = "B1")
    mdfTracer = convert(MF.MDFv2Tracer, tracer)
    @test MF.tracerName(mdfTracer) == ["Perimag"]
    @test MF.tracerSolute(mdfTracer) == ["Fe"]
    @test MF.tracerVendor(mdfTracer) == ["Micromod"]
    @test MF.tracerBatch(mdfTracer) == ["B1"]
    @test ismissing(MF.tracerConcentration(mdfTracer))
    @test ismissing(MF.tracerVolume(mdfTracer))
    @test isnothing(MF.tracerInjectionTime(mdfTracer))

    # The MDF stores the concentration in mol/L and the volume in L
    withAmount = MPIMeasurements.Tracer(name = "Perimag", concentration = 0.5u"mol/L", volume = 0.1u"mL")
    mdfWithAmount = convert(MF.MDFv2Tracer, withAmount)
    @test MF.tracerConcentration(mdfWithAmount) == [0.5]
    @test MF.tracerVolume(mdfWithAmount) ≈ [1e-4]

    # The reverse conversion assigns the per-tracer vectors of the MDF to the scalar
    # fields of Tracer, which fails
    @test_broken (try convert(MPIMeasurements.Tracer, mdfTracer).name == "Perimag"; catch; false; end)
  end
end
