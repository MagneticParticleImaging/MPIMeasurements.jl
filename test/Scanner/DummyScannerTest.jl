using ReusePatterns

@testset "Dummy scanner" begin
  scannerName_ = "TestDummyScanner"
  scanner = MPIScanner(scannerName_)

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
    @test generalParams.name == scannerName_
    @test generalParams.topology == "FFL"
    @test generalParams.gradient == 42u"T/m"
    @test scannerBoreSize(scanner) == 1337u"mm"
    @test scannerFacility(scanner) == "My awesome institute"
    @test scannerManufacturer(scanner) == "Me, Myself and I"
    @test scannerName(scanner) == scannerName_
    @test scannerTopology(scanner) == "FFL"
    @test scannerGradient(scanner) == 42u"T/m"
  end

  @testset "Devices" begin

    # TODO: add getDevices tests

    @testset "DAQ" begin
      daq = getDevice(scanner, "my_daq_id")
      @test typeof(daq) == concretetype(DummyDAQ) # This implies implementation details...
      @test daq.params.samplesPerPeriod == 1000
      @test daq.params.sendFrequency == 25u"kHz"
    end

    @testset "GaussMeter" begin
      gauss = getDevice(scanner, "my_gauss_id")
      @test typeof(gauss) == concretetype(DummyGaussMeter) # This implies implementation details...
    end

    @testset "Robots" begin
      #robot = getDevice(scanner, "my_robot_id")
    end

    @testset "SurveillanceUnit" begin
      surveillanceUnit = getDevice(scanner, "my_surveillance_unit_id")
      @test getTemperatures(surveillanceUnit) == 30.0u"°C"
      @test getACStatus(surveillanceUnit, scanner) == false # AC should be off in the beginning
      enableACPower(surveillanceUnit, scanner)
      @test getACStatus(surveillanceUnit, scanner) == true
      disableACPower(surveillanceUnit, scanner)
      @test getACStatus(surveillanceUnit, scanner) == false
      #@test resetDAQ(surveillanceUnit) # Can't be tested at the moment
    end

    @testset "TemperatureSensor" begin
      temperatureSensor = getDevice(scanner, "my_temperature_sensor_id")
      @test typeof(temperatureSensor) == concretetype(DummyTemperatureSensor) # This implies implementation details...
      @test numChannels(temperatureSensor) == 1
      @test getTemperature(temperatureSensor) == [42u"°C"]
      @test typeof(getTemperature(temperatureSensor)) == Vector{typeof(1u"°C")}
      @test getTemperature(temperatureSensor, 1) == 42u"°C"
      @test typeof(getTemperature(temperatureSensor, 1)) == typeof(1u"°C")
    end
  end
end