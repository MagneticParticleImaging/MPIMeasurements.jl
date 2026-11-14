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
  positions = MPIMeasurements.MPIFiles.RegularGridPositions([1, 1, 1], [1.0, 1.0, 1.0] .* u"mm", [0.0, 0.0, 0.0] .* u"mm")

  # Stores a measurement of `storedSequence` and returns a protocol of the same name
  # configured with `configuredSequence`, as after restarting with a changed configuration
  function restartedProtocol(protocolName)
    params = MultiSequenceSystemMatrixProtocolParams(sequences = [storedSequence], positions = positions, bgSequence = bgSequence, numBGMeas = 2)
    protocol = MultiSequenceSystemMatrixProtocol(name = protocolName, description = "", scanner = scanner_, params = params)
    init(protocol)
    MPIMeasurements.initMeasData(protocol)
    MPIMeasurements.store(protocol, 1)

    params = MultiSequenceSystemMatrixProtocolParams(sequences = [configuredSequence], positions = positions, bgSequence = bgSequence, numBGMeas = 2)
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

  # Protocol files are stored in the scratch space of the scanner
  protocolNames = ["MultiSequenceRestoreTest_use", "MultiSequenceRestoreTest_cancel"]
  protocolDirs = [joinpath(MPIMeasurements.dir(scanner_), protocolName) for protocolName in protocolNames]
  removeProtocolDirs() = foreach(protocolDir -> rm(protocolDir, recursive = true, force = true), protocolDirs)
  removeProtocolDirs()
  try
    @testset "Use stored sequences" testUseStoredSequences(protocolNames[1])
    @testset "Cancel" testCancel(protocolNames[2])
  finally
    # Memory-mapped files cannot be removed on Windows before the arrays are finalized
    GC.gc()
    removeProtocolDirs()
  end
  close(scanner_)
end
