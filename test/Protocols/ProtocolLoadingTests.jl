@testset "All configured protocols load" begin
  # The protocol parameters only need the configuration directory of the scanner, while
  # the devices of most configured scanners need hardware. Each protocol is therefore
  # loaded with a copy of its scanner configuration without devices.
  packageDir = normpath(@__DIR__, "..", "..")
  stubRoot = mktempdir()
  protocols = Tuple{String, String, String}[] # (protocol file, protocol name, scanner name)
  for configRoot in (joinpath(packageDir, "config"), testConfigDir)
    for scannerDir in readdir(configRoot, join = true)
      protocolDir = joinpath(scannerDir, "Protocols")
      isdir(protocolDir) || continue
      scannerName = basename(scannerDir)
      scannerFile = joinpath(scannerDir, "Scanner.toml")
      general = isfile(scannerFile) ? MPIMeasurements.TOML.parsefile(scannerFile)["General"] : Dict("name" => scannerName)
      stubDir = joinpath(stubRoot, scannerName)
      mkpath(stubDir)
      open(joinpath(stubDir, "Scanner.toml"), "w") do io
        MPIMeasurements.TOML.print(io, Dict("General" => general, "Devices" => Dict{String, Any}()))
      end
      for folder in ("Protocols", "Sequences")
        isdir(joinpath(scannerDir, folder)) && cp(joinpath(scannerDir, folder), joinpath(stubDir, folder))
      end
      for file in readdir(protocolDir, join = true)
        endswith(file, ".toml") && push!(protocols, (file, splitext(basename(file))[1], scannerName))
      end
    end
  end
  @test !isempty(protocols)

  addConfigurationPath(stubRoot)
  try
    @testset "$(relpath(file, packageDir))" for (file, protocolName, scannerName) in protocols
      scanner_ = MPIScanner(scannerName)
      @test isempty(scanner_.devices)
      @test Protocol(protocolName, scanner_) isa Protocol
    end
  finally
    filter!(!=(stubRoot), MPIMeasurements.scannerConfigurationPath)
    rm(stubRoot, recursive = true, force = true)
  end
end
