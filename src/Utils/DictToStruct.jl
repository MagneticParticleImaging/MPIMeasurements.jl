export tryuparse, from_dict


function tryuparse(val::Any)
  try
    return uparse(val)
  catch e
    return val
  end
end

function from_dict(type::DataType, dict::Dict)
  splattingDict = Dict{Symbol, Any}()
  for (key, value) in dict
    value = tryuparse.(value) # Convert with Unitful if applicable
    splattingDict[Symbol(key)] = value
  end
  
  return type(;splattingDict...)
end