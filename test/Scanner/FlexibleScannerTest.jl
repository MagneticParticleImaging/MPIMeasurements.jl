"""
Test the flexibility of the scanner instantiation

The scanner should be composable not only of devices defined within
MPIMeasurements, but also from the outside.
"""
@testset "Flexible scanner" begin
  ### This section can be in a different package, which is not coupled to MPIMeasurements.jl as a dependency
  export FlexibleDAQ, FlexibleDAQParams
  
  Base.@kwdef struct FlexibleDAQParams <: MPIMeasurements.DeviceParams
    samplesPerPeriod::Int
    sendFrequency::typeof(1u"kHz")
  end

  FlexibleDAQParams(dict::Dict) = params_from_dict(FlexibleDAQParams, dict)

  Base.@kwdef mutable struct FlexibleDAQ <: MPIMeasurements.AbstractDAQ
    "Unique device ID for this device as defined in the configuration."
    deviceID::String
    "Parameter struct for this devices read from the configuration."
    params::FlexibleDAQParams
    "Flag if the device is optional."
	  optional::Bool = false
    "Flag if the device is present."
	  present::Bool = false
    "Vector of dependencies for this device."
    dependencies::Dict{String, Union{Device, Missing}}
  end

  function MPIMeasurements.init(daq::FlexibleDAQ)
    @debug "Initializing flexible DAQ with ID `$(daq.deviceID)`."

    daq.present = true
  end
  
  MPIMeasurements.checkDependencies(daq::FlexibleDAQ) = true

  Base.close(daq::FlexibleDAQ) = nothing

  function MPIMeasurements.startTx(daq::FlexibleDAQ)
  end

  function MPIMeasurements.stopTx(daq::FlexibleDAQ)
  end

  function MPIMeasurements.setTxParams(daq::FlexibleDAQ, amplitude, phase; postpone=false)
  end

  function MPIMeasurements.currentFrame(daq::FlexibleDAQ)
      return 1;
  end

  function MPIMeasurements.currentPeriod(daq::FlexibleDAQ)
      return 1;
  end

  function MPIMeasurements.readData(daq::FlexibleDAQ, startFrame, numFrames)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
  end

  function MPIMeasurements.readDataPeriods(daq::FlexibleDAQ, startPeriod, numPeriods)
    uMeas=zeros(2,2,2,2)
    uRef=zeros(2,2,2,2)
    return uMeas, uRef
  end

  ### / External section

  scannerName_ = "TestFlexibleScanner"
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
      daq = getDevice(scanner, "my_daq_id")
      @test daq isa FlexibleDAQ
      @test daq.params.samplesPerPeriod == 1000
      @test daq.params.sendFrequency == 25u"kHz"
    end
  end

  close(scanner)
end