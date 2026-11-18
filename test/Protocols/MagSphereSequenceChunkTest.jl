@testset "MagSphere sequence chunks" begin
  baseFrequency = 125e6u"Hz"
  stepsPerFrame = 2
  dividerPerStep = 625_000
  triggerValues = repeat([0.9u"A", 0.0u"A"], 6)
  coilValues = repeat([1.0u"A", 2.0u"A", 3.0u"A", 4.0u"A", 5.0u"A", 6.0u"A"], inner=2)
  channels = TxChannel[
    StepwiseElectricalChannel(id="trigger", divider=dividerPerStep * length(triggerValues),
                              values=triggerValues, enable=Bool[]),
    StepwiseElectricalChannel(id="coil1", divider=dividerPerStep * length(coilValues),
                              values=coilValues, enable=Bool[]),
  ]
  sequence = Sequence(
    general=GeneralSettings(name="test", description="test", targetScanner="test",
                            baseFrequency=baseFrequency),
    fields=[MagneticField(id="test", channels=channels,
                          safeStartInterval=0.0u"s", safeEndInterval=0.0u"s",
                          safeErrorInterval=0.0u"s", control=false, decouple=false)],
    acquisition=AcquisitionSettings(channels=[RxChannel("rx1")], bandwidth=1.0u"Hz"),
  )

  firstChunk = MPIMeasurements.magSphereSequenceChunk(sequence, 0, 3)
  firstTrigger = only(filter(channel -> id(channel) == "trigger", stepwiseElectricalTxChannels(firstChunk)))
  @test length(MPIMeasurements.computeTriggerPatches(firstChunk)) == 3
  @test firstTrigger.divider == dividerPerStep * length(firstTrigger.values)
  @test MPIMeasurements.magSphereTriggerPeriod(firstChunk,
        MPIMeasurements.computeTriggerPatches(firstChunk)) ≈ 0.01

  resumedChunk = MPIMeasurements.magSphereSequenceChunk(sequence, 3, 5)
  resumedTrigger = only(filter(channel -> id(channel) == "trigger", stepwiseElectricalTxChannels(resumedChunk)))
  resumedCoil = only(filter(channel -> id(channel) == "coil1", stepwiseElectricalTxChannels(resumedChunk)))
  @test length(MPIMeasurements.computeTriggerPatches(resumedChunk)) == 2
  @test length(resumedTrigger.values) == stepsPerFrame * (5 - 3) + 1
  @test first(MPIMeasurements.computeTriggerPatches(resumedChunk)) == 2
  @test resumedTrigger.divider == dividerPerStep * length(resumedTrigger.values)
  @test MPIMeasurements.magSphereTriggerPeriod(resumedChunk,
        MPIMeasurements.computeTriggerPatches(resumedChunk)) ≈ 0.01
  @test resumedCoil.values == coilValues[2 * 3:2 * 5]
end