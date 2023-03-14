export tryuparse, dict_to_splatting, params_from_dict


function tryuparse(val::Any)
  try
    return uparse(val)
  catch e
    return val
  end
end

function tryuparse(val::Vector{T}) where {T}
  try
    return tryuparse.(val)
  catch e
    return val
  end
end

function parsePossibleURange(val::String)
  result = nothing
  if contains(val, ":")
    splitted = split(val, ":")
    if length(splitted) == 2
      result = uparse(splitted[1]):1*unit(uparse(splitted[1])):uparse(splitted[2])
    elseif length(splitted) == 3
      result = collect(uparse(splitted[1]):uparse(splitted[2]):uparse(splitted[3]))
    else
      throw(ArgumentError("Creating a range from more than three parameters is not possible."))
    end
  elseif contains(val, "fill")
    splitted = split(val, "(")
    splitted = split(splitted[2], ")", keepempty=true)
    splitted = split(splitted[1], ",")
    count = parse(Int64, splitted[2])
    repval = tryuparse.(splitted[1])
    if repval isa String
      repval = eval(Meta.parse(repval))
    end
    result = collect(fill(repval, count))
  else
    result = uparse.(val)
  end

  return result
end
parsePossibleURange(val::Vector{String}) = parsePossibleURange.(val)

function dict_to_splatting(dict::Dict)
  splattingDict = Dict{Symbol, Any}()
  for (key, value) in dict
    if value isa Dict # Do we need recursion here?
      specializedType = nothing
      doSpecialize = true
      for (subkey, subvalue) in value
        value[subkey] = tryuparse.(subvalue) # Convert with Unitful if applicable

        if isnothing(specializedType)
          specializedType = typeof(value[subkey])
        elseif typeof(value[subkey]) != specializedType
          doSpecialize = false
        end
      end

      # Check if the types are equal and we can convert the dict to a more specialized version
      if doSpecialize
        value = convert(Dict{String, specializedType}, value)
      end
    else
      value = tryuparse.(value) # Convert with Unitful if applicable
    end
    splattingDict[Symbol(key)] = value
  end

  return splattingDict
end

function dict_to_splatting(type::DataType, dict::Dict)
  splattingDict = Dict{Symbol, Any}()
  for (key, value) in dict
    if value isa Dict # Do we need recursion here?
      specializedType = nothing
      doSpecialize = true
      for (subkey, subvalue) in value
        value[subkey] = tryuparse.(subvalue) # Convert with Unitful if applicable

        if isnothing(specializedType)
          specializedType = typeof(value[subkey])
        elseif typeof(value[subkey]) != specializedType
          doSpecialize = false
        end
      end

      # Check if the types are equal and we can convert the dict to a more specialized version
      if doSpecialize
        value = convert(Dict{String, specializedType}, value)
      end
    else
      if fieldtype(type, Symbol(key)) == String
        value = String(value)
      else 
        value = tryuparse.(value) # Convert with Unitful if applicable
      end
    end
    splattingDict[Symbol(key)] = value
  end

  return splattingDict
end

function params_from_dict(type::DataType, dict::Dict)
  splattingDict = dict_to_splatting(type, dict)
  
  try
    return type(;splattingDict...)
  catch e
    if e isa UndefKeywordError
      throw(ScannerConfigurationError("The required field `$(e.var)` is missing in your configuration for a device with the params type `$type`."))
    else
      rethrow()
    end
  end
end

function stringToEnum(value::AbstractString, enumType::Type{T}) where {T <: Enum}
  stringInstances = string.(instances(enumType))
  # If lowercase is not sufficient one could try Unicode.normalize with casefolding
  index = findfirst(isequal(lowercase(value)), lowercase.(stringInstances))
  if isnothing(index)
    throw(ArgumentError("$value cannot be resolved to an instance of $(typeof(enumType)). Possible instances are: " * join(stringInstances, ", ", " and ") * "."))
  end
  return instances(enumType)[index]
end