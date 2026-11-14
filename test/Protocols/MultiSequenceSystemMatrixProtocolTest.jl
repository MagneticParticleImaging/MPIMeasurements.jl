@testset "MultiSequenceSystemMatrixProtocol restore" begin
  scanner_ = MPIScanner("TestSimpleSimulatedScanner")

  function simulatedSequence(amplitude)
    dict = MPIMeasurements.TOML.parsefile(joinpath(@__DIR__, "..", "Sequences", "TOML", "SimulatedScannerSequence.toml"))
    dict["Acquisition"]["numFrameAverages"] = 1
    dict["Fields"]["df"]["tx_main"]["c1"]["amplitude"] = [amplitude]
    return sequenceFromDict(dict)
  end
  storedSequence = simulatedSequence("0.012T")
  configuredSequence = simulatedSequence("0.010T")
  bgSequence = simulatedSequence("0.0T")
  otherBGSequence = simulatedSequence("0.001T")
  positions = MPIMeasurements.MPIFiles.RegularGridPositions([1, 1, 1], [1.0, 1.0, 1.0] .* u"mm", [0.0, 0.0, 0.0] .* u"mm")

  # Stores a measurement of `storedSequence` with `bgSequence` measured twice and returns a
  # protocol of the same name configured with the given parameters, as after restarting
  # with a changed configuration
  function restartedProtocol(protocolName; sequence = configuredSequence, bg = bgSequence, numBGMeas = 2)
    params = MultiSequenceSystemMatrixProtocolParams(sequences = [storedSequence], positions = positions, bgSequence = bgSequence, numBGMeas = 2)
    protocol = MultiSequenceSystemMatrixProtocol(name = protocolName, description = "", scanner = scanner_, params = params)
    init(protocol)
    MPIMeasurements.initMeasData(protocol)
    MPIMeasurements.store(protocol, 1)

    params = MultiSequenceSystemMatrixProtocolParams(sequences = [sequence], positions = positions, bgSequence = bg, numBGMeas = numBGMeas)
    protocol = MultiSequenceSystemMatrixProtocol(name = protocolName, description = "", scanner = scanner_, params = params)
    init(protocol)
    protocol.biChannel = BidirectionalChannel{ProtocolEvent}(4)
    return protocol
  end

  # Answers the next multiple-choice question with the choice named `answer`
  function answer(protocol, choice)
    user = BidirectionalChannel(protocol.biChannel)
    return @async begin
      question = take!(user)
      put!(user, ChoiceAnswerEvent(findfirst(==(choice), question.choices), question))
      question
    end
  end

  # Whether the question was answered; restore returns without a question if nothing differs
  answered(answerer) = timedwait(() -> istaskdone(answerer), 10.0) == :ok && fetch(answerer) isa MultipleChoiceEvent

  # The assertions are in functions, so that no reference to a protocol and its
  # memory-mapped signals remains when the protocol files are removed
  function testUseStoredSequences(protocolName)
    protocol = restartedProtocol(protocolName)
    answerer = answer(protocol, "Use")
    MPIMeasurements.restore(protocol)
    @test fetch(answerer) isa MultipleChoiceEvent
    @test protocol.restored
    @test protocol.params.sequences == [storedSequence]
    @test protocol.allSequences == [bgSequence, bgSequence, storedSequence, bgSequence, bgSequence]
    @test size(protocol.systemMeasState.signals, 4) == sum(acqNumFrames, protocol.allSequences)
    return nothing
  end

  function testCancel(protocolName)
    protocol = restartedProtocol(protocolName)
    answerer = answer(protocol, "Cancel")
    @test_throws MPIMeasurements.CancelException MPIMeasurements.restore(protocol)
    @test fetch(answerer) isa MultipleChoiceEvent
    @test !protocol.restored
    @test protocol.params.sequences == [configuredSequence]
    return nothing
  end

  # The stored background sequence and number of background measurements are compared
  # with the configured ones as well
  function testUseStoredBackground(protocolName; kwargs...)
    protocol = restartedProtocol(protocolName; sequence = storedSequence, kwargs...)
    answerer = answer(protocol, "Use")
    MPIMeasurements.restore(protocol)
    @test answered(answerer)
    @test protocol.restored
    @test protocol.params.bgSequence == bgSequence
    @test protocol.params.numBGMeas == 2
    @test protocol.allSequences == [bgSequence, bgSequence, storedSequence, bgSequence, bgSequence]
    return nothing
  end

  function testCancelBackground(protocolName)
    protocol = restartedProtocol(protocolName; sequence = storedSequence, bg = otherBGSequence)
    answerer = answer(protocol, "Cancel")
    @test_throws MPIMeasurements.CancelException MPIMeasurements.restore(protocol)
    @test answered(answerer)
    @test !protocol.restored
    @test protocol.params.bgSequence == otherBGSequence
    return nothing
  end

  function testMatching(protocolName)
    protocol = restartedProtocol(protocolName; sequence = storedSequence)
    MPIMeasurements.restore(protocol)
    @test protocol.restored
    @test !isready(BidirectionalChannel(protocol.biChannel)) # no question asked
    return nothing
  end

  # Protocol files are stored in the scratch space of the scanner
  protocolNames = ["MultiSequenceRestoreTest_" * suffix for suffix in
    ["use", "cancel", "bg", "nobg", "numbg", "cancelbg", "match"]]
  protocolDirs = [joinpath(MPIMeasurements.dir(scanner_), protocolName) for protocolName in protocolNames]
  removeProtocolDirs() = foreach(protocolDir -> rm(protocolDir, recursive = true, force = true), protocolDirs)
  removeProtocolDirs()
  try
    @testset "Use stored sequences" testUseStoredSequences(protocolNames[1])
    @testset "Cancel" testCancel(protocolNames[2])
    @testset "Use stored background sequence" testUseStoredBackground(protocolNames[3]; bg = otherBGSequence)
    @testset "Use stored background sequence instead of none" testUseStoredBackground(protocolNames[4]; bg = nothing)
    @testset "Use stored number of background measurements" testUseStoredBackground(protocolNames[5]; numBGMeas = 1)
    @testset "Cancel background" testCancelBackground(protocolNames[6])
    @testset "Matching parameters" testMatching(protocolNames[7])
  finally
    # Memory-mapped files cannot be removed on Windows before the arrays are finalized
    GC.gc()
    removeProtocolDirs()
  end
  close(scanner_)
end
