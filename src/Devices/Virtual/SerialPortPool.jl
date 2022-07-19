export SerialPortPool, SerialPortPoolParams

Base.@kwdef struct SerialPortPoolParams <: DeviceParams
  addressPool::Vector{String}
  timeout_ms::Integer = 1000
end
SerialPortPoolParams(dict::Dict) = params_from_dict(SerialPortPoolParams, dict)

Base.@kwdef mutable struct SerialPortPool <: Device
  @add_device_fields SerialPortPoolParams
  activePool::Vector{String} = []
end

neededDependencies(::SerialPortPool) = []
optionalDependencies(::SerialPortPool) = []

function _init(pool::SerialPortPool)
  pool.activePool = pool.params.addressPool
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
  if haskey(portMap, description)
    port = portMap[description]
    if in(port, pool.activePool)
      try
        sd = SerialDevice(port; kwargs...)
        reserveSerialPort(pool, port)
        return sd
      catch e
        @error e
      end
    end
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

function close(pool::SerialPortPool)
  # NOP
end