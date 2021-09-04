import Base: convert

export MPIScanner, MPIScannerGeneral, scannerBoreSize, scannerFacility,
       scannerManufacturer, scannerName, scannerTopology, scannerGradient,
       name, configDir, generalParams, getDevice, getDevices, getGUIMode,
       getSequenceList

"""Recursively find all concrete types"""
function deepsubtypes(type::DataType)
  subtypes_ = subtypes(type)
  allSubtypes = subtypes_
  for subtype in subtypes_
    subsubtypes_ = deepsubtypes(subtype)
    allSubtypes = vcat(allSubtypes, subsubtypes_)
  end
  return allSubtypes
end

"""
Retrieve the concrete type of a given supertype corresponding to a given string
"""
function getConcreteType(supertype_::DataType, type::String)
  knownTypes = deepsubtypes(supertype_)
  foundImplementation = nothing
  for Implementation in knownTypes
    if string(Implementation) == type
      foundImplementation = Implementation
    end
  end

  if !isnothing(foundImplementation)
    return foundImplementation
  else
    error("The type implied by the string `$type` could not be retrieved since its device struct was not found.")
  end
end

"""
Initiate devices from the given configuration dictionary

The device types are referenced by strings matching their device struct name.
All device structs are supplied with the device ID and the corresponding
device configuration struct.
"""
function initiateDevices(devicesParams::Dict{String, Any})
  devices = Dict{String, Device}()

  # Get implementations for all devices in the specified order
  for deviceID in devicesParams["initializationOrder"]
    if haskey(devicesParams, deviceID)
      params = devicesParams[deviceID]
      deviceType = pop!(params, "deviceType")

      dependencies_ = Dict{String, Union{Device, Missing}}()
      if haskey(params, "dependencies")
        deviceDepencencies = pop!(params, "dependencies")
        for dependencyID in deviceDepencencies
          dependencies_[dependencyID] = missing
        end
      end

      DeviceImpl = getConcreteType(Device, deviceType)
      DeviceParamsImpl = getConcreteType(DeviceParams, deviceType*"Params") # Assumes the naming convention of ending with [...]Params!
      paramsInst = DeviceParamsImpl(params)
      devices[deviceID] = DeviceImpl(deviceID=deviceID, params=paramsInst, dependencies=dependencies_) # All other fields must have default values!
    else
      throw(ScannerConfigurationError("The device ID `$deviceID` was not found in the configuration. Please check your configuration."))
    end
  end

  # Set dependencies for all devices
  for device in values(devices)
    for dependencyID in keys(dependencies(device))
      device.dependencies[dependencyID] = devices[dependencyID]
    end
    
    if !checkDependencies(device)
      throw(ScannerConfigurationError("Unspecified dependency error in device with ID `$(deviceID(device))`."))
    end
  end

  # Initiate all devices in the specified order
  for deviceID in devicesParams["initializationOrder"]
    init(devices[deviceID])
  end

  return devices
end

"""
General description of the scanner

Note: The fields correspond to the root section of an MDF file.
"""
Base.@kwdef struct MPIScannerGeneral
  boreSize::typeof(1u"mm")
  facility::String
  manufacturer::String
  name::String
  topology::String
  gradient::typeof(1u"T/m")
  datasetStore::String
end

"""
Central part for setting up a scanner.

TODO: Add more details on instantiation
"""
mutable struct MPIScanner
  name::AbstractString
  configDir::AbstractString
  generalParams::MPIScannerGeneral
  devices::Dict{AbstractString, Device}
  guiMode::Bool

  function MPIScanner(name::AbstractString; guimode=false)
    # Search for scanner configurations of the given name in all known configuration directories
    # If you want to add a configuration directory, please use addConfigurationPath(path::String)
    filename = nothing
    configDir = nothing
    for path in scannerConfigurationPath
      configDir = joinpath(path, name)
      if isdir(configDir)
        filename = joinpath(configDir, "Scanner.toml")
        break
      end
    end

    if isnothing(filename)
      throw(ScannerConfigurationError("Could not find a valid configuration for scanner with name `$name`. Search path contains the following directories: $scannerConfigurationPath."))
    end

    @info "Instantiating scanner `$name` from configuration file at `$filename`."

    params = TOML.parsefile(filename)
    generalParams = params_from_dict(MPIScannerGeneral, params["General"])
    @assert generalParams.name == name "The folder name and the scanner name in the configuration do not match."
    devices = initiateDevices(params["Devices"])

    return new(name, configDir, generalParams, devices, guimode)
  end
end

function Base.close(scanner::MPIScanner)
  for device in getDevices(Device)
    close(device)
  end
end

name(scanner::MPIScanner) = scanner.name #TODO: Duplication with scanner name
configDir(scanner::MPIScanner) = scanner.configDir
generalParams(scanner::MPIScanner) = scanner.generalParams
getDevice(scanner::MPIScanner, deviceID::String) = scanner.devices[deviceID]

function getDevices(scanner::MPIScanner, deviceType::DataType)
  matchingDevices = Vector{Device}()
  for (deviceID, device) in scanner.devices
    if typeof(device) <: deviceType
      push!(matchingDevices, device)
    end
  end
  return matchingDevices
end
function getDevices(scanner::MPIScanner, deviceType::String)
  knownDeviceTypes = deepsubtypes(Device)
  deviceTypeSearched = knownDeviceTypes[findall(type->string(type)==deviceType, knownDeviceTypes)][1]
  return getDevices(scanner, deviceTypeSearched)
end

getGUIMode(scanner::MPIScanner) = scanner.guiMode

scannerBoreSize(scanner::MPIScanner) = scanner.generalParams.boreSize
scannerFacility(scanner::MPIScanner) = scanner.generalParams.facility
scannerManufacturer(scanner::MPIScanner) = scanner.generalParams.manufacturer
scannerName(scanner::MPIScanner) = scanner.generalParams.name
scannerTopology(scanner::MPIScanner) = scanner.generalParams.topology
scannerGradient(scanner::MPIScanner) = scanner.generalParams.gradient

function getSequenceList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "Sequences")
  if isdir(path)
    return String[ splitext(seq)[1] for seq in filter(a->contains(a,".toml"),readdir(path))] 
  else
    return String[]
  end
end

function MPIFiles.Sequence(scanner::MPIScanner, name::AbstractString)
  path = joinpath(configDir(scanner), "Sequences", name*".toml")
  if !isfile(path)
    error("Sequence $(path) not available!")
  end
  return sequenceFromTOML(path)
end