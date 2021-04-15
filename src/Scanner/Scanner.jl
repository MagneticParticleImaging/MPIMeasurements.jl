using Pkg.TOML

import Base: convert

export MPIScanner, MPIScannerGeneral, scannerBoreSize, scannerFacility,
       scannerManufacturer, scannerName, scannerTopology, scannerGradient,
       getName, getConfigDir, getGeneralParams, getDevice, getDevices, getGUIMode

"""
Automatic conversion from string to Unitful quantities.

Note: This is implicitly used in initiateDevices.
"""
function Base.convert(type::Type{T}, value::String) where T<:Quantity
  parsedValue = uparse(value)
  parsedType = typeof(parsedValue)
  if parsedType == type
    return parsedValue
  else
    error("The required type of $type does not match the type $parsedType implied by the value `$value`.")
  end
end

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
Retrieve the type corresponding to a given string

Note: This is using eval() in order to achieve its goal.
      Do not load configurations from untrusted sources!
"""
function getConcreteType(type::String)
  return eval(Meta.parse(type))
end

"""
Initiate devices from the given configuration dictionary

The device types are referenced by strings matching their device struct name.
All device structs are supplied with the device ID and the corresponding
device configuration struct.
"""
function initiateDevices(devicesParams::Dict{String, Any})
  devices = Dict{String, Device}()

  for deviceID in devicesParams["initializationOrder"]
    if haskey(devicesParams, deviceID)
      params = devicesParams[deviceID]
      deviceType = pop!(params, "deviceType")

      DeviceImpl = getConcreteType(deviceType)
      DeviceParamsImpl = getConcreteType(deviceType*"Params") # Assumes the naming convention of ending with [...]Params!
      paramsInst = from_dict(DeviceParamsImpl, params)
      devices[deviceID] = DeviceImpl(deviceID, paramsInst)
    else
      @error "The device ID `$deviceID` was not found in the configuration. Please check your configuration."
    end
  end

  return devices
end

"""
General description of the scanner

Note: The fields correspond to the root section of an MDF file.
"""
@option struct MPIScannerGeneral
  boreSize::typeof(1u"mm")
  facility::String
  manufacturer::String
  name::String
  topology::String
  gradient::typeof(1u"T/m")
end

mutable struct MPIScanner
  name::String
  configDir::String
  generalParams::MPIScannerGeneral
  devices::Dict{String, Device}
  guiMode::Bool

  function MPIScanner(name::String; guimode=false)
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
      error("Could not find a valid configuration for scanner with name `$name`. Search path contains the following directories: $scannerConfigurationPath.")
    end

    params = TOML.parsefile(filename)
    generalParams = from_dict(MPIScannerGeneral, params["General"])
    devices = initiateDevices(params["Devices"])

    return new(name, configDir, generalParams, devices, guimode)

    # @info "Init SurveillanceUnit"
    # surveillanceUnit = loadDeviceIfAvailable(params, SurveillanceUnit, "SurveillanceUnit")

    # @info "Init DAQ"   # Restart the DAQ if necessary
    # waittime = 45
    # daq = nothing
    # daq = loadDeviceIfAvailable(params, AbstractDAQ, "DAQ")
    # try
    #   daq = loadDeviceIfAvailable(params, AbstractDAQ, "DAQ")
    # catch e
    #   @info "connection to DAQ could not be established! Restart (wait $(waittime) seconds...)!"
    #   if !isnothing(surveillanceUnit) && typeof(surveillanceUnit) != DummySurveillanceUnit
    #     resetDAQ(surveillanceUnit)
    #     sleep(waittime)
    #   end
    #   daq = loadDeviceIfAvailable(params, DAbstractDAQAQ, "DAQ")
    # end

    # @info "Init Robot"
    # if guimode
    #   params["Robot"]["doReferenceCheck"] = false
    # end
    # robot = loadDeviceIfAvailable(params, Robot, "Robot")
    # @info "Init GaussMeter"
    # gaussmeter = loadDeviceIfAvailable(params, GaussMeter, "GaussMeter")
    # @info "Init Safety"
    # safety = loadDeviceIfAvailable(params, RobotSetup, "Safety") 
    # @info "Init TemperatureSensor"
    # temperatureSensor = loadDeviceIfAvailable(params, TemperatureSensor, "TemperatureSensor")   
    # @info "All components initialized!"

    # return new(file,params,generalParams,daq,robot,gaussmeter,safety,surveillanceUnit,temperatureSensor)
  end
end

function Base.close(scanner::MPIScanner)
  for device in getDevices(Device)
    close(device)
  end
end

getName(scanner::MPIScanner) = scanner.name
getConfigDir(scanner::MPIScanner) = scanner.configDir
getGeneralParams(scanner::MPIScanner) = scanner.generalParams
getDevice(scanner::MPIScanner, deviceID::String) = scanner.devices[deviceID]

function getDevices(scanner::MPIScanner, deviceType::T) where T <: Device
  matchingDevices = Dict{String, Device}()
  for (deviceID, device) in scanner.devices
    if typeof(device) <: deviceType
      matchingDevices[deviceID] = device
    end
  end
end
function getDevices(scanner::MPIScanner, deviceType::String)
  knownDeviceTypes = deepsubtypes(Device)
  deviceTypeSearched = findall(type->string(type)==deviceType, knownDeviceTypes)
  return getDevices(scanner, deviceTypeSearched)
end

getGUIMode(scanner::MPIScanner) = scanner.guiMode

scannerBoreSize(scanner::MPIScanner) = scanner.generalParams.boreSize
scannerFacility(scanner::MPIScanner) = scanner.generalParams.facility
scannerManufacturer(scanner::MPIScanner) = scanner.generalParams.manufacturer
scannerName(scanner::MPIScanner) = scanner.generalParams.name
scannerTopology(scanner::MPIScanner) = scanner.generalParams.topology
scannerGradient(scanner::MPIScanner) = scanner.generalParams.gradient
