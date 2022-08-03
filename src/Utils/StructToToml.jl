export toTOML, toDict, toDict!, toDictValue

function toTOML(fileName::AbstractString, value)
  open(fileName, "w") do io
    toTOML(io, value)
  end
end

function toTOML(io::IO, value)
  dict = toDict(value)
  TOML.print(io, dict)
end

function toDict(value)
  dict = Dict{String, Any}()
  return toDict!(dict, value)
end

function toDict!(dict, value)
  for field in fieldnames(typeof(value))
    dict[String(field)] = toDictValue(getproperty(value, field))
  end
  return dict
end

toDictValue(x) = x
toDictValue(x::T) where {T<:Quantity} = filter(!isspace, (string(x)))
toDictValue(x::T) where {T<:Enum} = string(x)
toDictValue(x::Array) = toDictValue.(x)