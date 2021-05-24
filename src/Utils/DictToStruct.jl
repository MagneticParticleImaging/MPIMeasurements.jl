export tryuparse, from_dict


function tryuparse(val::Any)
  try
    return uparse(val)
  catch e
    return val
  end
end

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

function params_from_dict(type::DataType, dict::Dict)
  splattingDict = dict_to_splatting(dict)
  
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