import Base: convert

export MPIScanner, MPIScannerGeneral, scannerBoreSize, scannerFacility,
       scannerManufacturer, scannerName, scannerTopology, scannerGradient, scannerDatasetStore,
       name, configDir, generalParams, getDevice, getDevices, getSequenceList,
       asyncMeasurement, SequenceMeasState, asyncProducer, prepareAsyncMeasurement,
       getProtocolList, setProtocol, getTransferFunctionList

"""
    $(SIGNATURES)

Recursively find all concrete types of the given type.
"""
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
    $(SIGNATURES)

Retrieve the concrete type of a given supertype corresponding to a given string.
"""
function getConcreteType(supertype_::DataType, type::String)
  knownTypes = deepsubtypes(supertype_)
  foundImplementation = nothing
  for Implementation in knownTypes
    if string(Implementation) == type
      foundImplementation = Implementation
    end
  end
  return foundImplementation
end

"""
    $(SIGNATURES)

Initiate devices from the given configuration dictionary.

The device types are referenced by strings matching their device struct name.
All device structs are supplied with the device ID and the corresponding
device configuration struct.
"""
function initiateDevices(devicesParams::Dict{String, Any}; robust = false)
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
      if isnothing(DeviceImpl)
        error("The type implied by the string `$deviceType` could not be retrieved since its device struct was not found.")
      end
      validateDeviceStruct(DeviceImpl)

      paramsInst = getFittingDeviceParamsType(params, deviceType)
      if isnothing(paramsInst)
        error("Could not find a fitting device parameter struct for device ID `$deviceID`.")
      end

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
      throw(ScannerConfigurationError("Unspecified dependency error in device with "
                                     *"ID `$(deviceID(device))`. The device depends "
                                     *"on the following device IDs: $(keys(device.dependencies))"))
    end
  end

  # Initiate all devices in the specified order
  for deviceID in devicesParams["initializationOrder"]
    try
      init(devices[deviceID])
      if !isOptional(devices[deviceID]) && !isPresent(devices[deviceID])
        @error "The device with ID `$deviceID` should be present but isn't."
      end
    catch e
      if !robust
        throw(e)
      else
        @warn e
      end
    end
  end

  return devices
end

function getFittingDeviceParamsType(params::Dict{String, Any}, deviceType::String)
  paramKeys = Symbol.(keys(params))
  tempDeviceParams = []
  paramsRoot = getConcreteType(DeviceParams, deviceType*"Params") # Assumes the naming convention of ending with [...]Params!
  push!(tempDeviceParams, paramsRoot)
  length(deepsubtypes(paramsRoot)) == 0 || push!(tempDeviceParams, deepsubtypes(paramsRoot)...)

  fittingDeviceParams = []
  for paramType in tempDeviceParams
    #Can't easily see default values for fields -> Just try out all types
    #for constructor in methods(paramType)
    #  if issubset(paramKeys, Base.kwarg_decl(constructor))
    #    push!(fittingDeviceParams, paramType)
    #    break
    #  end
    #end
    try
      tempParams = paramType(params)
      push!(fittingDeviceParams, tempParams)
    catch ex
      # NOP
    end
  end

  if length(fittingDeviceParams) == 1
    return fittingDeviceParams[1]
  else
    return nothing
  end
end

"""
    $(SIGNATURES)

General description of the scanner.

Note: The fields correspond to the root section of an MDF file.
"""
Base.@kwdef struct MPIScannerGeneral
  "Bore size of the scanner."
  boreSize::Union{typeof(1u"mm"), Nothing} = nothing
  "Facility where the scanner is located."
  facility::String = "N.A."
  "Manufacturer of the scanner."
  manufacturer::String = "N.A."
  "Name of the scanner"
  name::String
  "Topology of the scanner, e.g. FFL or FFP."
  topology::String = "N.A."
  "Gradient of the scanners selection field."
  gradient::Union{typeof(1u"T/m"), Nothing} = nothing
  "Path of the dataset store."
  datasetStore::String = ""
  "Default sequence of the scanner."
  defaultSequence::String = ""
  "Default protocol of the scanner."
  defaultProtocol::String = ""
  "Location of the scanner's transfer function."
  transferFunction::String = ""
  "Thread ID of the producer thread."
  producerThreadID::Int32 = 2
  "Thread ID of the consumer thread."
  consumerThreadID::Int32 = 3
  "Thread ID of the producer thread."
  protocolThreadID::Int32 = 4
end

"""
    $(SIGNATURES)

Basic description of a scanner.
"""
mutable struct MPIScanner
  "Name of the scanner"
  name::String
  "Path to the used configuration directory."
  configDir::String
  "General parameters of the scanner like its bore size or gradient."
  generalParams::MPIScannerGeneral
  "Device instances instantiated by the scanner from its configuration."
  devices::Dict{AbstractString, Device}

  """
    $(SIGNATURES)

  Initialize a scanner by its name.
  """
  function MPIScanner(name::AbstractString; robust=false)
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

    @debug "Instantiating scanner `$name` from configuration file at `$filename`."

    params = TOML.parsefile(filename)
    generalParams = params_from_dict(MPIScannerGeneral, params["General"])
    @assert generalParams.name == name "The folder name and the scanner name in the configuration do not match."
    devices = initiateDevices(params["Devices"], robust = robust)

    scanner = new(name, configDir, generalParams, devices)

    return scanner
  end
end

"""
    $(SIGNATURES)

Close the devices when closing the scanner.
"""
function Base.close(scanner::MPIScanner)
  for device in getDevices(scanner, Device)
    close(device)
  end
end

"Name of the scanner"
name(scanner::MPIScanner) = scanner.name

"Path to the used configuration directory."
configDir(scanner::MPIScanner) = scanner.configDir

"General parameters of the scanner like its bore size or gradient."
generalParams(scanner::MPIScanner) = scanner.generalParams

"Location of the scanner's transfer function."
transferFunction(scanner::MPIScanner) = scanner.generalParams.transferFunction

"Check, whether the scanner has a transfer function defined."
hasTransferFunction(scanner::MPIScanner) = transferFunction(scanner) != ""

"""
    $(SIGNATURES)

Retrieve a device by its `deviceID`.
"""
getDevice(scanner::MPIScanner, deviceID::String) = scanner.devices[deviceID]

"""
    $(SIGNATURES)

Retrieve all devices of a specific `deviceType`. Returns an empty vector if none are found
"""
function getDevices(scanner::MPIScanner, deviceType::Type{<:Device})
  matchingDevices = Vector{Device}()
  for (deviceID, device) in scanner.devices
    if typeof(device) <: deviceType && isPresent(device)
      push!(matchingDevices, device)
    end
  end
  return matchingDevices
end
function getDevices(scanner::MPIScanner, deviceType::String)
  knownDeviceTypes = deepsubtypes(Device)
  push!(knownDeviceTypes, Device)
  deviceTypeSearched = knownDeviceTypes[findall(type->string(type)==deviceType, knownDeviceTypes)][1]
  return getDevices(scanner, deviceTypeSearched)
end

"""
$(SIGNATURES)

Retrieve all devices of a specific `deviceType` if it can be unambiguously retrieved. Returns nothing if no such device can be found and throws an error if multiple devices fit the type.
"""
function getDevice(scanner::MPIScanner, deviceType::Type{<:Device})
  devices = getDevices(scanner, deviceType)
  if length(devices) > 1
    error("The scanner has more than one $(string(deviceType)) device. Therefore, a single $(string(deviceType)) cannot be retrieved unambiguously.")
  elseif length(devices) == 0
    return nothing
  else
    return devices[1]
  end
end

"Bore size of the scanner."
scannerBoreSize(scanner::MPIScanner) = scanner.generalParams.boreSize

"Facility where the scanner is located."
scannerFacility(scanner::MPIScanner) = scanner.generalParams.facility

"Manufacturer of the scanner."
scannerManufacturer(scanner::MPIScanner) = scanner.generalParams.manufacturer

"Name of the scanner"
scannerName(scanner::MPIScanner) = scanner.generalParams.name

"Topology of the scanner, e.g. FFL or FFP."
scannerTopology(scanner::MPIScanner) = scanner.generalParams.topology

"Gradient of the scanners selection field."
scannerGradient(scanner::MPIScanner) = scanner.generalParams.gradient

"Path of the dataset store."
scannerDatasetStore(scanner::MPIScanner) = scanner.generalParams.datasetStore

"Default sequence of the scanner."
defaultSequence(scanner::MPIScanner) = scanner.generalParams.defaultSequence

"Default protocol of the scanner."
defaultProtocol(scanner::MPIScanner) = scanner.generalParams.defaultProtocol

"""
    $(SIGNATURES)

Retrieve a list of all sequences available for the scanner.
"""
function getSequenceList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "Sequences")
  if isdir(path)
    return String[ splitext(seq)[1] for seq in filter(a->contains(a,".toml"),readdir(path))]
  else
    return String[]
  end
end


"""
    $(SIGNATURES)

Constructor for a sequence of `name` from `configDir`.
"""
function MPIFiles.Sequence(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "Sequences", name*".toml")
  if !isfile(path)
    error("Sequence $(path) not available!")
  end
  return sequenceFromTOML(path)
end

"""
    $(SIGNATURES)

Constructor for a sequence of `name` from the configuration directory specified for the scanner.
"""
MPIFiles.Sequence(scanner::MPIScanner, name::AbstractString) = Sequence(configDir(scanner), name)

function getTransferFunctionList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "TransferFunctions")
  if isdir(path)
    return String[ splitext(seq)[1] for seq in filter(a->contains(a,".h5"),readdir(path))]
  else
    return String[]
  end
end

function MPIFiles.TransferFunction(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "TransferFunctions", name*".h5")
  if !isfile(path)
    error("TransferFunction $(path) not available!")
  end
  return TransferFunction(path)
end

MPIFiles.TransferFunction(scanner::MPIScanner) = TransferFunction(configDir(scanner),transferFunction(scanner))

#### Protocol ####
function getProtocolList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "Protocols/")
  if isdir(path)
    return String[ splitext(proto)[1] for proto in filter(a->contains(a,".toml"),readdir(path))]
  else
    return String[]
  end
end

function execute(scanner::MPIScanner, protocol::Protocol)
  return execute(protocol, scanner.generalParams.protocolThreadID)
end
