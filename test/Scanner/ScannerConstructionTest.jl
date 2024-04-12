@testset "Scanner Construction" begin
  # Mandatory fields missing from device struct
  @testset "Incomplete Device Struct" begin
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingID")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingDependencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingOptional")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingPresent")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingParams")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestBrokenDeviceMissingConfigFile")
  end

  # Dependencies are checked correctly
  @testset "Incorrect Dependency" begin
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceMissingDependencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceWrongDependencies")
    @test_throws MPIMeasurements.ScannerConfigurationError MPIScanner("TestDeviceUninitDependencies")
  end

  @testset "Working Scanner" begin
    sName = "TestDeviceWorkingScanner"
    mpiScanner = MPIScanner(sName)
    
    @testset verbose = true "General" begin
      @test name(mpiScanner) == sName
      @test configDir(mpiScanner) == joinpath(testConfigDir, sName)
      @test scannerBoreSize(mpiScanner) == 1337u"mm"
      @test scannerFacility(mpiScanner) == "My awesome institute"
      @test scannerManufacturer(mpiScanner) == "Me, Myself and I"
      @test scannerName(mpiScanner) == sName
      @test scannerTopology(mpiScanner) == "FFL"
      @test scannerGradient(mpiScanner) == 42u"T/m"  
    end

    @testset verbose = true "Devices" begin
      # getDevice(s) Function behave similar (enough)
      @test issetequal(getDevices(mpiScanner, "Device"), getDevices(mpiScanner, Device))
      @test length(getDevices(mpiScanner, "Device")) == length(getDevices(mpiScanner, Device))
      @test issetequal(getDevices(mpiScanner, "TestDevice"), getDevices(mpiScanner, TestDevice))
      @test length(getDevices(mpiScanner, "TestDevice")) == length(getDevices(mpiScanner, TestDevice))
      @test getDevices(mpiScanner, TestDependencyDevice)[1] == getDevice(mpiScanner, "testDependency")
      # Unused devices dont show up
      @test length(getDevices(mpiScanner, Device)) == 3
      
      # Returns nothing/empty if not found
      @test isnothing(getDevice(mpiScanner, RedPitayaDAQ))
      @test isempty(getDevices(mpiScanner, RedPitayaDAQ))
      
      # Multiple of same device
      @test_throws ErrorException getDevice(mpiScanner, TestDevice)
      testDevices = getDevices(mpiScanner, TestDevice)
      @test length(testDevices) == 2
      @test testDevices[1] != testDevices[2]

      # init and _init were called for all devices
      @test all([x.initRan for x in getDevices(mpiScanner, Device)])
      @test all([MPIMeasurements.isPresent(x) for x in getDevices(mpiScanner, Device)])

      # Dependencies are set correctly
      dependencyDevice = getDevice(mpiScanner, "testDependency")
      testDevice = getDevice(mpiScanner, "testDevice")
      @test hasDependency(dependencyDevice, TestDevice)
      @test length(dependencies(dependencyDevice)) == 1
      @test dependency(dependencyDevice, TestDevice) == testDevice

      # Parameter are set correctly
      _params = MPIMeasurements.params(testDevice)
      @test _params.stringValue == "BAR"
      @test _params.stringArray == ["MPI", "Measurements", "Test", "String"]
      @test _params.enumValue == BAR
      @test _params.enumArray == [FOO, FOO, BAR]
      @test _params.unitValue == 11.0u"V"
      @test _params.unitArray == [0.5u"V", 0.4u"V", 1.0u"V"]
      @test _params.primitiveValue == 2
      @test _params.primitveArray == [1, 2, 3, 4, 5, 6]
      @test _params.arrayArray == [[10, 20]u"mm", [30, 40]u"mm", [50, 60]u"mm"]
    end

    @testset "Subfolders" begin
      # Sequences
      listSeq = getSequenceList(mpiScanner)
      @test issetequal(listSeq, ["1DSequence", "1DSequence2"])
      @test_throws ErrorException Sequence(mpiScanner, "DoesNotExist")
      @test MPIMeasurements.name(Sequence(mpiScanner, listSeq[1])) == listSeq[1]
      
      # Protocols
      listProto = getProtocolList(mpiScanner)
      @test issetequal(listProto, ["MPIMeasurement"])
      @test_throws MPIMeasurements.ProtocolConfigurationError Protocol("DoesNotExist", mpiScanner)
      @test MPIMeasurements.name(Protocol(listProto[1], mpiScanner)) == listProto[1]
    end
    @testset "Device (Re-)Loading" begin
      dependencyDevice = getDevice(mpiScanner, "testDependency")
      dependencyDevice.present = false
      testDevice = getDevice(mpiScanner, "testDevice")
      testDevice.present = false

      init(mpiScanner, [dependencyDevice])
      dependencyDevice = getDevice(mpiScanner, "testDependency")
      testDevice = getDevice(mpiScanner, "testDevice")

      @test MPIMeasurements.isPresent(testDevice) == true
      @test MPIMeasurements.isPresent(dependencyDevice) == true

      dependencyDevice.present = false
      testDevice.present = false

      init(mpiScanner, ["testDependency"])
      dependencyDevice = getDevice(mpiScanner, "testDependency")
      testDevice = getDevice(mpiScanner, "testDevice")

      @test MPIMeasurements.isPresent(testDevice) == true
      @test MPIMeasurements.isPresent(dependencyDevice) == true
    end

  end

  @testset "Load Device from TOML" begin
    devices = Devices("TestDeviceWorkingScanner", ["testDevice", "testDependency"])
    # Dependencies are set correctly
    dependencyDevice = devices[2]
    testDevice = devices[1]
    @test hasDependency(dependencyDevice, TestDevice)
    @test length(dependencies(dependencyDevice)) == 1
    @test dependency(dependencyDevice, TestDevice) == testDevice

    # Parameter are set correctly
    _params = MPIMeasurements.params(testDevice)
    @test _params.stringValue == "BAR"
    @test _params.stringArray == ["MPI", "Measurements", "Test", "String"]
    @test _params.enumValue == BAR
    @test _params.enumArray == [FOO, FOO, BAR]
    @test _params.unitValue == 11.0u"V"
    @test _params.unitArray == [0.5u"V", 0.4u"V", 1.0u"V"]
    @test _params.primitiveValue == 2
    @test _params.primitveArray == [1, 2, 3, 4, 5, 6]
    @test _params.arrayArray == [[10, 20]u"mm", [30, 40]u"mm", [50, 60]u"mm"]
  end


end