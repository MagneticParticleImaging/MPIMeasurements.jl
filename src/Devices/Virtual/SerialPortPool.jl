export SerialPortPool, SerialPortPoolParams, SerialPortPoolListedParams, SerialPortPoolBlacklistParams

abstract type SerialPortPoolParams <: DeviceParams end 

Base.@kwdef struct SerialPortPoolListedParams <: SerialPortPoolParams
  addressPool::Vector{String}
  timeout_ms::Integer = 1000
end
SerialPortPoolListedParams(dict::Dict) = params_from_dict(SerialPortPoolListedParams, dict)

Base.@kwdef struct SerialPortPoolBlacklistParams <: SerialPortPoolParams
  blacklist::Vector{String}
  timeout_ms::Integer = 1000
end
SerialPortPoolBlacklistParams(dict::Dict) = params_from_dict(SerialPortPoolBlacklistParams, dict)


Base.@kwdef mutable struct SerialPortPool <: Device
  @add_device_fields SerialPortPoolParams
  activePool::Vector{String} = []
end

neededDependencies(::SerialPortPool) = []
optionalDependencies(::SerialPortPool) = []

function _init(pool::SerialPortPool)
  pool.activePool = initPool(pool.params)
end

function initPool(params::SerialPortPoolListedParams)
  return params.addressPool
end

function initPool(params::SerialPortPoolBlacklistParams)
  return filter(x->!in(x, params.blacklist), get_port_list())  
end

function getSerialDevice(pool::SerialPortPool, queryStr::String, reply::String; kwargs...)
  result = nothing
  for address in pool.activePool
    try
      sd = SerialDevice(address; kwargs...)
      response=query(sd, queryStr)
      if response == reply
        result = sd
        reserveSerialPort(pool, address)
        break
      else
        close(sd)
      end
    catch ex
      @warn ex
      try
        close(sd)
      catch e
        # NOP
      end
    end
  end
  return result
end

function getSerialDevice(pool::SerialPortPool, description::String; kwargs...)
  portMap = descriptionMap()
  fittingPorts = filter(contains(description), keys(portMap))
  if length(fittingPorts) > 1
    throw(ScannerConfigurationError("Can not unambiguously find a port for description $description"))
  elseif length(fittingPorts) == 1
    port = portMap[first(fittingPorts)]
    if in(port, pool.activePool)
      try
        sd = SerialDevice(port; kwargs...)
        reserveSerialPort(pool, port)
        return sd
      catch e
        @error e
      end
    end
  else
    throw(ScannerConfigurationError("No suitable SerialPort for `$description` found in SerialPortPool!"))
  end
  return nothing
end

function descriptionMap()
  result = Dict{String, String}()
  ports = get_port_list()
  for port in ports
    result[LibSerialPort.sp_get_port_description(SerialPort(port))] = port
  end
  return result
end

function reserveSerialPort(pool::SerialPortPool, port::String)
  deleteat!(pool.activePool, findall(x->x==port, pool.activePool))
end

function returnSerialPort(pool::SerialPortPool, port::String)
  if (in(port, pool.params.addressPool) && !in(port, pool.activePool))
    push!(pool.activePool, port)
  end
end


function initSerialDevice(device::Device, query::String, response::String)
  pool = nothing
  if hasDependency(device, SerialPortPool)
    pool = dependency(device, SerialPortPool)
    sd = getSerialDevice(pool, query, response; serial_device_splatting(device.params)...)
    if isnothing(sd)
      throw(ScannerConfigurationError("Device $(deviceID(device)) failed to connect to serial port."))
    end
    return sd
  else
    throw(ScannerConfigurationError("Device $(deviceID(device)) requires a SerialPortPool dependency but has none."))
  end
end

function initSerialDevice(device::Device, description::String)
  pool = nothing
  if hasDependency(device, SerialPortPool)
    pool = dependency(device, SerialPortPool)
    sd = getSerialDevice(pool, description; serial_device_splatting(device.params)...)
    if isnothing(sd)
      throw(ScannerConfigurationError("Device $(deviceID(device)) failed to connect to serial port with description $description."))
    end
    return sd
  else
    throw(ScannerConfigurationError("Device $(deviceID(device)) requires a SerialPortPool dependency but has none."))
  end
end

function close(pool::SerialPortPool)
  # NOP
end