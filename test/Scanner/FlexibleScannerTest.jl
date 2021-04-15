using ReusePatterns
using Configurations

"""
Test the flexibility of the scanner instantiation

The scanner should be composable not only of devices defined within
MPIMeasurements, but also from the outside.
"""
@testset "Flexible scanner" begin
  ### This section can be in a different package, which is not coupled to MPIMeasurements.jl as a dependency
  export FlexibleDAQ
  
  @option struct FlexibleDAQParams <: MPIMeasurements.DeviceParams
    samplesPerPeriod::Int
    sendFrequency::typeof(1u"kHz")
  end

  @quasiabstract struct FlexibleDAQ <: MPIMeasurements.AbstractDAQ
    handle::Union{String, Nothing}

    function FlexibleDAQ(deviceID::String, params::FlexibleDAQParams)
      return new(deviceID, params, nothing)
    end
  end

  function startTx(daq::FlexibleDAQ)
  end

  function stopTx(daq::FlexibleDAQ)
  end

  function setTxParams(daq::FlexibleDAQ, amplitude, phase; postpone=false)
  end

  function currentFrame(daq::FlexibleDAQ)
      return 1;
  end

  function currentPeriod(daq::FlexibleDAQ)
      return 1;
  end

  function readData(daq::FlexibleDAQ, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
  end

  function readDataPeriods(daq::FlexibleDAQ, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
  end
  refToField(daq::FlexibleDAQ, d::Int64) = 0.0

  ### / External section

  scannerName_ = "TestFlexibleScanner"
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

    @testset "DAQ" begin
      daq = getDevice(scanner, "my_daq_id")
      @test typeof(daq) == concretetype(FlexibleDAQ) # This implies implementation details...
      @test daq.params.samplesPerPeriod == 1000
      @test daq.params.sendFrequency == 25u"kHz"
    end

    @testset "GaussMeter" begin
      gauss = getDevice(scanner, "my_gauss_id")
      @test typeof(gauss) == concretetype(DummyGaussMeter) # This implies implementation details...
    end
  end
end