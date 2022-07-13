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

function getSerialPort(pool::SerialPortPool, query::String, reply::String, baudrate::Integer; ndatabits::Integer = 8, parity::SPParity = SP_PARITY_NONE, nstopbits::Integer = 1)
  result = nothing
  for address in pool.activePool
    try
      sp = SerialPort(address)
      open(sp)
      set_speed(sp, baudrate)
      set_frame(sp, ndatabits = ndatabits, parity = parity, nstopbits=nstopbits)
      flush(sp)
      write(sp, query)
      response=readuntil(sp, last(reply), pool.params.timeout_ms)
      @show response
      if response == reply
        result = sp
        reserveSerialPort(pool, address)
        break
      else
        close(sp)
      end
    catch ex
      try
        close(sp)
      catch e
        # NOP
      end
    end
  end
  return result
end

function getSerialPort(pool::SerialPortPool, description::String,  baudrate::Integer; ndatabits::Integer = 8, parity::SPParity = SP_PARITY_NONE, nstopbits::Integer = 1)
  portMap = descriptionMap()
  if haskey(portMap, description)
    port = portMap[description]
    if in(port, pool.activePool)
      try
        sp = SerialPort(port)
        open(sp)
        set_speed(sp, baudrate)
        set_frame(sp, ndatabits = ndatabits, parity = parity, nstopbits=nstopbits)
        reserveSerialPort(pool, port)
        return sp
      catch e
        @error e
      end
    end
  end
  return nothing
end

function descriptionMap()
  result = Dict{String, String}()
  ports = sp_list_ports()
  for port in unsafe_wrap(Array, ports, 64, own=false)
    port == C_NULL && return result
    result[sp_get_port_description(port)] = sp_get_port_name(port)
  end
  sp_free_port_list(ports)
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