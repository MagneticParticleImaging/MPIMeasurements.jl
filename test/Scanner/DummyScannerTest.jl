@testset "Dummy scanner" begin
  scannerName_ = "TestDummyScanner"
  scanner = MPIScanner(scannerName_)

  @testset "Meta" begin
    @test name(scanner) == scannerName_
    @test configDir(scanner) == joinpath(testConfigDir, scannerName_)
    @test getGUIMode(scanner::MPIScanner) == false
  end

  @testset "General" begin
    generalParams_ = generalParams(scanner)
    @test generalParams_ isa MPIScannerGeneral
    @test generalParams_.boreSize == 1337u"mm"
    @test generalParams_.facility == "My awesome institute"
    @test generalParams_.manufacturer == "Me, Myself and I"
    @test generalParams_.name == scannerName_
    @test generalParams_.topology == "FFL"
    @test generalParams_.gradient == 42u"T/m"
    @test scannerBoreSize(scanner) == 1337u"mm"
    @test scannerFacility(scanner) == "My awesome institute"
    @test scannerManufacturer(scanner) == "Me, Myself and I"
    @test scannerName(scanner) == scannerName_
    @test scannerTopology(scanner) == "FFL"
    @test scannerGradient(scanner) == 42u"T/m"
  end

  @testset "Devices" begin

    @testset "DAQ" begin
      @test_broken 0 # Dummy DAQ is being transformed to Red Pitaya version
      # daq = getDevice(scanner, "my_daq_id")
      # @test daq isa DummyDAQ
      # @test daq.params.samplesPerPeriod == 1000
      # @test daq.params.frequency == 25u"kHz"

      # daqs = getDevices(scanner, AbstractDAQ)
      # @test daqs[1] == daq
      # @test getDevices(scanner, "AbstractDAQ") == daqs
      # @test getDAQs(scanner) == daqs
      # @test getDAQ(scanner) == daq #TODO: Add testset that checks errors with multiple devices
    end

    @testset "GaussMeter" begin
      gaussMeter = getDevice(scanner, "my_gauss_id")
      @test gaussMeter isa SimulatedGaussMeter
      @test getXValue(gaussMeter) == 1.0u"mT"
      @test getYValue(gaussMeter) == 2.0u"mT"
      @test getZValue(gaussMeter) == 3.0u"mT"
      @test getXYZValues(gaussMeter) == [1.0, 2.0, 3.0]u"mT"

      gaussMeters = getDevices(scanner, GaussMeter)
      @test gaussMeters[1] == gaussMeter
      @test getDevices(scanner, "GaussMeter") == gaussMeters
      @test getGaussMeters(scanner) == gaussMeters
      @test getGaussMeter(scanner) == gaussMeter #TODO: Add testset that checks errors with multiple devices
    end

    @testset "Robots" begin
      rob = getDevice(scanner, "my_robot_id")
      @test rob isa SimulatedRobot

      # @test state(rob)==:INIT # In a scanner setting the robot is setup within init and is thus in state DISABLED
      @test getPosition(rob)==[0,0,0]u"mm"
      @test dof(rob)==3

      @test namedPositions(rob)["origin"]==[0,0,0]u"mm"
      @test collect(keys(namedPositions(rob))) == ["origin"]

      #setup(rob) # In a scanner setting the robot is setup within init
      @test state(rob)==:DISABLED
      @test_throws RobotStateError moveAbs(rob, [1,1,1]u"mm")
      @test_throws RobotStateError setup(rob)

      @test !isReferenced(rob)
      enable(rob)
      @test_throws RobotReferenceError moveAbs(rob, [1,1,1]u"mm")
      @test_throws RobotReferenceError gotoPos(rob, "origin")
      @test_throws RobotAxisRangeError moveRel(rob, [1,0,0]u"m") # out of range for axis 1

      @test_logs (:warn, "Performing relative movement in unreferenced state, cannot validate coordinates! Please proceed carefully and perform only movements which are safe!") moveRel(rob, [10,0,0]u"mm")

      doReferenceDrive(rob)
      @test isReferenced(rob)
      moveAbs(rob, [1,1,1]u"mm")
      teachPos(rob, "pos1")
      @test issetequal(keys(namedPositions(rob)), ["origin", "pos1"])

      moveAbs(rob, 2u"mm",2u"mm",2u"mm")
      teachPos(rob, "pos2")
      gotoPos(rob, "pos1")
      @test getPosition(rob) == [1,1,1]u"mm"

      moveAbs(rob, [1,1,1]u"mm", 10u"mm/s")
      @test_throws RobotDOFError moveAbs(rob, [1,1]u"mm")
      reset(rob)
      @test state(rob)==:INIT
    end

    @testset "SurveillanceUnit" begin
      surveillanceUnit = getDevice(scanner, "my_surveillance_unit_id")
      @test surveillanceUnit isa DummySurveillanceUnit
      @test getTemperatures(surveillanceUnit) == 30.0u"°C"
      @test getACStatus(surveillanceUnit, scanner) == false # AC should be off in the beginning
      enableACPower(surveillanceUnit, scanner)
      @test getACStatus(surveillanceUnit, scanner) == true
      disableACPower(surveillanceUnit, scanner)
      @test getACStatus(surveillanceUnit, scanner) == false
      #@test resetDAQ(surveillanceUnit) # Can't be tested at the moment

      surveillanceUnits = getDevices(scanner, SurveillanceUnit)
      @test surveillanceUnits[1] == surveillanceUnit
      @test getDevices(scanner, "SurveillanceUnit") == surveillanceUnits
      @test getSurveillanceUnits(scanner) == surveillanceUnits
      @test getSurveillanceUnit(scanner) == surveillanceUnit #TODO: Add testset that checks errors with multiple devices
    end

    @testset "TemperatureSensor" begin
      temperatureSensor = getDevice(scanner, "my_temperature_sensor_id")
      @test temperatureSensor isa DummyTemperatureSensor
      @test numChannels(temperatureSensor) == 1
      @test getTemperature(temperatureSensor) == [42u"°C"]
      @test typeof(getTemperature(temperatureSensor)) == Vector{typeof(1u"°C")}
      @test getTemperature(temperatureSensor, 1) == 42u"°C"
      @test typeof(getTemperature(temperatureSensor, 1)) == typeof(1u"°C")

      temperatureSensors = getDevices(scanner, TemperatureSensor)
      @test temperatureSensors[1] == temperatureSensor
      @test getDevices(scanner, "TemperatureSensor") == temperatureSensors
      @test getTemperatureSensors(scanner) == temperatureSensors
      @test getTemperatureSensor(scanner) == temperatureSensor #TODO: Add testset that checks errors with multiple devices
    end

    @testset "Amplifier" begin
      amp = getDevice(scanner, "my_amplifier_id")
      @test amp isa SimulatedAmplifier

      @test state(amp) == false # default
      @test mode(amp) == AMP_VOLTAGE_MODE # Safe default
      @test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE # Safe default
      @test matchingNetwork(amp) == 1 # default

      turnOn(amp)
      @test state(amp) == true

      turnOff(amp)
      @test state(amp) == false

      mode(amp, AMP_CURRENT_MODE)
      @test mode(amp) == AMP_CURRENT_MODE

      mode(amp, AMP_VOLTAGE_MODE)
      @test mode(amp) == AMP_VOLTAGE_MODE

      voltageMode(amp, AMP_HIGH_VOLTAGE_MODE)
      @test voltageMode(amp) == AMP_HIGH_VOLTAGE_MODE

      voltageMode(amp, AMP_LOW_VOLTAGE_MODE)
      @test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE

      matchingNetwork(amp, 2)
      @test matchingNetwork(amp) == 2

      @test temperature(amp) == 25.0u"°C"

      toCurrentMode(amp)
      @test mode(amp) == AMP_CURRENT_MODE

      toVoltageMode(amp)
      @test mode(amp) == AMP_VOLTAGE_MODE

      toLowVoltageMode(amp)
      @test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE

      toHighVoltageMode(amp)
      @test voltageMode(amp) == AMP_HIGH_VOLTAGE_MODE
    end
  end
end