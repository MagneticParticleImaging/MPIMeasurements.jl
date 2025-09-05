import Base: convert

export MPIScanner, MPIScannerGeneral, scannerBoreSize, scannerFacility,
       scannerManufacturer, scannerName, scannerTopology, scannerGradient, scannerDatasetStore,
       name, configDir, generalParams, getDevice, getDevices, Device, Devices, getSequenceList,
       asyncMeasurement, SequenceMeasState, asyncProducer,
       getProtocolList, getTransferFunctionList

"""
    $(SIGNATURES)

Recursively find all concrete types of the given type.
"""
function deepsubtypes(type::Type)
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
concreteTypesCache = Dict{String, Type}()
function getConcreteType(supertype_::Type, type::String)
  if haskey(concreteTypesCache, type)
    return concreteTypesCache[type]
  end
  knownTypes = deepsubtypes(supertype_)
  foundImplementation = nothing
  for Implementation in knownTypes
    if string(Implementation) == type
      foundImplementation = Implementation
    end
  end
  push!(concreteTypesCache, type=>foundImplementation)
  return foundImplementation
end

"""
    $(SIGNATURES)

Initiate devices from the given configuration dictionary.

The device types are referenced by strings matching their device struct name.
All device structs are supplied with the device ID and the corresponding
device configuration struct.
"""
function initiateDevices(configDir::AbstractString, devicesParams::Dict{String, Any}; robust = false, order::Vector{String} = get(devicesParams, "initializationOrder", String[]))
  devices = Dict{String, Device}()

  # Get implementations for all devices in the specified order
  for deviceID in order
    params = nothing
    configFile = nothing
    if haskey(devicesParams, deviceID)
      params = devicesParams[deviceID]
      configFile = joinpath(configDir, "Scanner.toml")
    else
      params = deviceParams(configDir, deviceID)
      configFile = joinpath(configDir, "Devices", deviceID*".toml")
    end

    if !isnothing(params)
      dependencies = filter(kv -> in(kv[1], get(params, "dependencies", String[])), devices)
      device = Device(deviceID, params; dependencies = dependencies, robust = robust, configFile = configFile)
 
      if !isOptional(device) && !isPresent(device)
        @error "The device with ID `$deviceID` should be present but isn't."
      end

      devices[deviceID] = device
    else 
      throw(ScannerConfigurationError("The device ID `$deviceID` was not found in the configuration. Please check your configuration."))
    end

  end

  return devices
end

function Device(deviceID::String, deviceParams::Dict{String, Any}; dependencies::Dict{String, Device}, robust::Bool = false, configFile = nothing)
  device = nothing
  params = copy(deviceParams)

  # Remove meta-data keys from dict
  deviceType = pop!(params, "deviceType")
  deviceDepencencies = pop!(params, "dependencies", String[])

  try 
    # Set dependencies
    dependencies_ = Dict{String, Union{Device, Missing}}()
    for dependencyID in deviceDepencencies
      dependencies_[dependencyID] = get(dependencies, dependencyID, missing)
    end

    # Find valid device struct
    DeviceImpl = getConcreteType(Device, deviceType)
    if isnothing(DeviceImpl)
      error("The type implied by the string `$deviceType` could not be retrieved since its device struct was not found.")
    end
    validateDeviceStruct(DeviceImpl)

    # Find fitting parameter struct
    paramsInst = getFittingDeviceParamsType(params, deviceType)
    if isnothing(paramsInst)
      error("Could not find a fitting device parameter struct for device ID `$deviceID`.")
    end

    # Construct device
    device = DeviceImpl(deviceID=deviceID, params=paramsInst, dependencies=dependencies_, configFile = configFile) # All other fields must have default values!
    
    # Initialize device
    checkDependencies(device)
    init(device)

  catch e
    if !robust
      rethrow()
    else
      @warn e
    end
  end

  return device
end

function getFittingDeviceParamsType(params::Dict{String, Any}, deviceType::String)
  tempDeviceParams = []
  paramsRoot = getConcreteType(DeviceParams, deviceType*"Params") # Assumes the naming convention of ending with [...]Params!
  push!(tempDeviceParams, paramsRoot)
  length(deepsubtypes(paramsRoot)) == 0 || push!(tempDeviceParams, deepsubtypes(paramsRoot)...)

  fittingDeviceParams = []
  lastException = nothing
  lastBacktrace = nothing
  for (i, paramType) in enumerate(tempDeviceParams)
    try
      tempParams = paramType(copy(params))
      push!(fittingDeviceParams, tempParams)
    catch ex
      lastException = ex
      lastBacktrace = Base.catch_backtrace()
    end
  end

  if length(fittingDeviceParams) == 1
    return fittingDeviceParams[1]
  elseif length(fittingDeviceParams) == 0 && !isnothing(lastException)
    Base.printstyled("ERROR: "; color=:red, bold=true)
    Base.showerror(stdout, lastException)
    Base.show_backtrace(stdout, lastBacktrace)
    throw("The above error occured during device creation!")
  else
    return nothing
  end
end

function dependenciesDFS(deviceIDs::Vector{String}, params::Dict{String, Any})
  stack = String[deviceIDs...]
  devices = String[]
  
  # Find all dependencies
  while !isempty(stack)
    device = pop!(stack)
    if !in(device, devices)
      push!(devices, device)
      push!(stack, get(params[device], "dependencies", String[])...)
    end
  end

  return devices
end

"""
    $(SIGNATURES)

General description of the scanner.

Note: The fields correspond to the root section of an MDF file.

$FIELDS
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
  "Default protocol of the scanner."
  defaultProtocol::String = ""
  "Thread ID of the producer thread."
  producerThreadID::Int32 = 2
  "Thread ID of the consumer thread."
  consumerThreadID::Int32 = 3
  "Thread ID of the producer thread."
  protocolThreadID::Int32 = 4
  "Thread ID of the dedicated serial port thread"
  serialThreadID::Int32 = 2
end

"""
    $(SIGNATURES)

Basic description of a scanner.

$(FIELDS)
"""
mutable struct MPIScanner
  "Name of the scanner"
  name::String
  "Path to the used configuration file."
  configFile::String
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
    configDir = findConfigDir(name)
    params = getScannerParams(configDir)
    
    @info "Instantiating scanner `$name` from configuration file at `$(joinpath(configDir, "Scanner.toml"))`."
    generalParams = params_from_dict(MPIScannerGeneral, params["General"])
    @assert generalParams.name == name "The folder name and the scanner name in the configuration do not match."
    devices = initiateDevices(configDir, params["Devices"], robust = robust)

    scanner = new(name, joinpath(configDir, "Scanner.toml"), generalParams, devices)

    return scanner
  end
end

function findConfigDir(name::AbstractString)
  for path in scannerConfigurationPath
    configDir = joinpath(path, name)
    if isdir(configDir)
      return configDir
    end
  end
  return nothing
end

function getScannerParams(configDir::String)
  filename = isnothing(configDir) ? nothing : joinpath(configDir, "Scanner.toml")
  if isnothing(filename)
    throw(ScannerConfigurationError("Could not find a valid configuration for scanner with name `$name`. Search path contains the following directories: $scannerConfigurationPath."))
  end
  return TOML.parsefile(filename)
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

"Path to the used configuration file"
configFile(scanner::MPIScanner) = scanner.configFile

"Path to the used configuration directory."
configDir(scanner::MPIScanner) = dirname(scanner.configFile)

"General parameters of the scanner like its bore size or gradient."
generalParams(scanner::MPIScanner) = scanner.generalParams

"""
    $(SIGNATURES)

Retrieve a device by its `deviceID`.
"""
getDevice(scanner::MPIScanner, deviceID::String) = scanner.devices[deviceID]

"""
    $(SIGNATURES)

Initialize and retrieve a device by its `deviceID` from a scanners configuration file. Also initializes the devices dependency tree according to the initialization order defined in the configuration file.
"""
function Device(scannerName::String, deviceID::String; kwargs...) 
  devices = Devices(scannerName, [deviceID]; kwargs...)
  return isempty(devices) ? nothing : first(devices)
end
"""
    $(SIGNATURES)

Retrieve all devices of a specific `deviceType`. Returns an empty vector if none are found
"""
function getDevices(scanner::MPIScanner, deviceType::Type{T}) where {T<:Device}
  matchingDevices = Vector{T}()
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
function getDevices(scanner::MPIScanner, deviceIDs::Vector{String})
  matchingDevices = Vector{Device}()
  for (deviceID, device) in scanner.devices
    if in(deviceID, deviceIDs) && isPresent(device)
      push!(matchingDevices, device)
    end
  end
  return matchingDevices
end

"""
    $(SIGNATURES)

Initialize and retrieve devices by their`deviceID` from a scanners configuration file. Also initializes the devices dependency trees according to the initialization order defined in the configuration file..
"""
function Devices(scannerName::String, deviceIDs::Vector{String}; kwargs...)
  configDir = findConfigDir(scannerName)
  params = getScannerParams(configDir)["Devices"]

  devices = dependenciesDFS(deviceIDs, params)

  order = filter(x -> in(x, devices), params["initializationOrder"])
  
  deviceDict = initiateDevices(configDir, params; kwargs..., order = order)

  return [deviceDict[id] for id in deviceIDs]
end

"""
$(SIGNATURES)

Retrieve a device of a specific `deviceType` if it can be unambiguously retrieved. Returns nothing if no such device can be found and throws an error if multiple devices fit the type.
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

function getDevice(f::Function, scanner::MPIScanner, arg)
  device = getDevice(scanner, arg)
  if !isnothing(device)
    f(device)
  else
    return nothing
  end
end

function getDevices(f::Function, scanner::MPIScanner, arg)
  c_ex = nothing
  devices = getDevices(scanner, arg)
  if !isnothing(devices) && !isempty(devices)
    for device in devices
      try
        f(device)
      catch ex
        if isnothing(c_ex)
          c_ex = CompositeException()
        end
        push!(c_ex, ex)
      end
    end
  else
    return nothing
  end
  if !isnothing(c_ex)
    throw(c_ex)
  end
  nothing
end


init(scanner::MPIScanner, devices::Vector{<:Device}; kwargs...) = init(scanner, map(deviceID, devices); kwargs...)
"""
    $SIGNATURES

(Re-)initializes the given devices of a Scanner according to the current configuration file. This also initializes all dependencies of the given devices.
This does not initialize devices that themselves depend on the given devices.
"""
function init(scanner::MPIScanner, deviceIDs::Vector{String} = getDeviceIDs(scanner); kwargs...)
  params = getScannerParams(configDir(scanner))["Devices"]

  devices = dependenciesDFS(deviceIDs, params)
  order = filter(x -> in(x, devices), params["initializationOrder"])
  
  getDevices(close, scanner, order)

  deviceDict = initiateDevices(configDir(scanner), params; kwargs..., order = order)

  for (id, device) in deviceDict
    scanner.devices[id] = device
  end

  return scanner
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

"Default protocol of the scanner."
defaultProtocol(scanner::MPIScanner) = scanner.generalParams.defaultProtocol

"""
    $(SIGNATURES)

Retrieve a list of all device IDs available for the scanner.
"""
function getDeviceIDs(scanner::MPIScanner)
  return map(String, collect(keys(scanner.devices)))
end

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
function Sequence(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "Sequences", name*".toml")
  if !isfile(path)
    error("Sequence $(path) not available!")
  end
  return sequenceFromTOML(path)
end
function Sequences(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "Sequences", name)
  if !isdir(path)
    error("Sequence-Directory $(path) not available!")
  end
  paths = sort(collect(readdir(path, join = true)), lt=natural)
  return [sequenceFromTOML(p) for p in paths]
end
"""
    $(SIGNATURES)

Constructor for a sequence of `name` from the configuration directory specified for the scanner.
"""
Sequence(scanner::MPIScanner, name::AbstractString) = Sequence(configDir(scanner), name)
Sequences(scanner::MPIScanner, name::AbstractString) = Sequences(configDir(scanner), name)

function Sequence(scanner::MPIScanner, dict::Dict)
  sequence = sequenceFromDict(dict)
  if name(scanner) == targetScanner(sequence)
    return sequence
  end
  throw(ScannerConfigurationError("Target scanner of sequence differs from given scanner:
                                   $(name(scanner)) != $(targetScanner(sequence))"))
end

function deviceParams(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "Devices", name*".toml")
  if !isfile(path)
    return nothing
  end
  return TOML.parsefile(path)
end

deviceParams(scanner::MPIScanner, name::AbstractString) = deviceParams(configDir(scanner), name)


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
