export MagSphere, MagSphereParams, MagSphereDirectParams, MagSpherePoolParams, MagSphereDescriptionParams
abstract type MagSphereParams <: DeviceParams end

Base.@kwdef struct MagSphereDirectParams <: MagSphereParams
  portAddress::String
  bufferSize::Int64 = 2048
  @add_serial_device_fields "\r\n"
end
MagSphereDirectParams(dict::Dict) = params_from_dict(MagSphereDirectParams, dict)

Base.@kwdef struct MagSphereDescriptionParams <: MagSphereParams
  description::String
  bufferSize::Int64 = 2048
  @add_serial_device_fields "\r\n"
end
MagSphereDescriptionParams(dict::Dict) = params_from_dict(MagSphereDescriptionParams, dict)

struct MagSphereResult
  timestamp::Float64
  data::Array{typeof(1.0u"T")}
end

Base.@kwdef mutable struct MagSphere <: GaussMeter
  @add_device_fields MagSphereParams
  sd::Union{SerialDevice, Nothing} = nothing

  ch::Channel{MagSphereResult} = Channel{MagSphereResult}(1)
  task::Union{Nothing, Task} = nothing
  lock::ReentrantLock = ReentrantLock()
end

neededDependencies(::MagSphere) = []
optionalDependencies(::MagSphere) = [SerialPortPool]

function _init(gauss::MagSphere)
  params = gauss.params
  sd = initSerialDevice(gauss, params)
  @info "Connection to MagSphere established."        
  gauss.sd = sd
end

function initSerialDevice(gauss::MagSphere, params::MagSphereDirectParams)
  sd = SerialDevice(params.portAddress; serial_device_splatting(params)...)
  return sd
end

function initSerialDevice(gauss::MagSphere, params::MagSphereDescriptionParams)
  sd = initSerialDevice(gauss, params.description)
  return sd
end

take!(gauss::MagSphere) = isready(gauss.ch) ? take!(gauss.ch) : error("Empty channel")

function enable(gauss::MagSphere)
  lock(gauss.lock) do
    disable(gauss)
    gauss.ch = Channel{MagSphereResult}(gauss.params.bufferSize)
    gauss.task = Threads.@spawn readData(gauss)
    bind(gauss.ch, gauss.task)
  end
end

function disable(gauss::MagSphere)
  lock(gauss.lock) do
    try 
      close(gauss.ch)
      wait(gauss.task)
    catch e
      @error e
    end 
  end
end

function readData(gauss::MagSphere)
  discard(gauss.sd)
  while isopen(gauss.ch)

    # Sleep while channel is full
    while length(gauss.ch.data) >= gauss.ch.sz_max
      sleep(0.01)
    end

    try
      line = receive(gauss.sd)
      result = parseData(gauss, line)
      if !isnothing(result)
        put!(gauss.ch, result)
      end
    catch e
      @debug e
    end
  end
end

function parseData(gauss::MagSphere, line::String)
  components = split(line, ";")
  # Unexpected format
  if length(components) != 87
    return nothing
  end

  timestamp = tryparse(Float64, components[1])
  isnothing(timestamp) && return nothing

  data = zeros(typeof(1.0u"T"), 3, 86)
  for i = 1:86
    xyz = split(components[i+1], ",")

    if length(xyz) != 3
      return nothing
    end

    xyz = tryparse.(Float64, xyz)
    data[:, i] = xyz./1e6 .* 1.0u"T"
  end

  return MagSphereResult(timestamp, data)
end

function getXYZValues(gauss::MagSphere; tries = 10)
  discard(gauss.sd)
  i = 1
  while i < tries
    try 
      line = receive(gauss.sd)
      result = parseData(gauss, line)
      if !isnothing(result)
        return result.data
      end  
    catch e
      @debug e
    end
    i+=1
  end
  return nothing
end

close(gauss::MagSphere) = close(gauss.sd)