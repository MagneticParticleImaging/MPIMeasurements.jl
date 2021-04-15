@testset "Dummy scanner" begin
  scannerName_ = "TestDummyScanner"
  scanner = MPIScanner("TestDummyScanner")

  @testset "Meta" begin
    @test getName(scanner) == scannerName_
    @test getConfigDir(scanner) == joinpath(testConfigDir, scannerName_)
    @test getGUIMode(scanner::MPIScanner) == false
  end

  @testset "General" begin
    generalParams = getGeneralParams(scanner)
    @test typeof(generalParams) == MPIScannerGeneral
    @test generalParams.boreSize == 1337u"mm"
    @test generalParams.facility == "My awesome institute"
    @test generalParams.manufacturer == "Me, Myself and I"
    @test generalParams.name == "TestDummyScanner"
    @test generalParams.topology == "FFL"
    @test generalParams.gradient == 42u"T/m"
    @test scannerBoreSize(scanner) == 1337u"mm"
    @test scannerFacility(scanner) == "My awesome institute"
    @test scannerManufacturer(scanner) == "Me, Myself and I"
    @test scannerName(scanner) == "TestDummyScanner"
    @test scannerTopology(scanner) == "FFL"
    @test scannerGradient(scanner) == 42u"T/m"
  end

  @testset "Devices" begin

    @testset "DAQ" begin
      daq = getDevice(scanner, "my_daq_id")
      @test typeof(daq) == DummyDAQ
      @test daq.samplesPerPeriod == 1000
      @test daq.sendFrequency == 25u"kHz"
    end

    @testset "GaussMeter" begin
      gauss = getDevice(scanner, "my_gauss_id")
      @test typeof(gauss) == DummyGaussMeter
    end
  end
end