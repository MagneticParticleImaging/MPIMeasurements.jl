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

function parsePossibleURange(val::AbstractString)
  result = nothing
  if contains(val, ":")
    splitted = split(val, ":")
    if length(splitted) == 2
      result = collect(uparse(splitted[1]):1*unit(uparse(splitted[1])):uparse(splitted[2]))
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
parsePossibleURange(val::AbstractVector) = parsePossibleURange.(val)

"""
    parse_into_tf(value)

Parse the `calibration` or `transferFunction` entry of a DAQ channel. `value` is
either the name of a `.h5` file (returned unchanged and loaded later), a single
value with unit (a frequency-independent transfer function) or a dict that maps
frequencies to values with unit. A frequency key is either a plain number in Hz
(`"25000"`) or a number with a unit built from Hz or s (`"25kHz"`, `"25 kHz"`,
`"40 μs^-1"`). Angular frequencies (e.g. `"1 rad/s"`, `"1 °/s"`, `"60 rpm"`) throw a
`ScannerConfigurationError`.

Example of a frequency-dependent `calibration` in the Scanner.toml (keys that
contain a decimal point must be quoted, otherwise TOML reads them as nested keys):

```toml
[Devices.rp_cluster.excitation.calibration]
"25kHz" = "20.5V/T"
"26.042 kHz" = "20.7V/T"
27000 = "21.0V/T"
```
"""
function parse_into_tf(value::String)
  if occursin(".h5", value) # case 1: filename to transfer function, the TF will be read the first time calibration() is called, (done in _init(), to prevent delays while using the device)
    calibration_tf = value
  else # case 2: single value, extended into transfer function with no frequency dependency
    calibration_value = uparse(value)
    calibration_tf = TransferFunction([0,Inf],ComplexF64[ustrip(calibration_value), ustrip(calibration_value)], units=[unit(calibration_value)])
  end
  return calibration_tf
end

function parse_into_tf(value::Dict)
  calibValues = uparse.(values(value))
  calibValues = uconvert.(unit(first(calibValues)), calibValues)
  frequencies = parse_tf_frequency.(keys(value))
  if !allunique(frequencies)
    throw(ScannerConfigurationError("The frequency keys $(collect(keys(value))) of the transfer function contain the same frequency more than once."))
  end
  sortedIdx = sortperm(frequencies)

  calibValues = calibValues[sortedIdx]
  frequencies = frequencies[sortedIdx]
  calibration_tf = TransferFunction(frequencies, ComplexF64.(ustrip.(calibValues)), units=[unit(first(calibValues))])
  return calibration_tf
end

# A plain number is a frequency in Hz; otherwise the key is a number followed by a frequency unit.
function parse_tf_frequency(key::AbstractString)
  freq = tryparse(Float64, key)
  isnothing(freq) || return freq
  m = match(r"^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*(\S.*?)\s*$", key)
  quantity = nothing
  if !isnothing(m)
    unit_ = try
      uparse(m.captures[2])
    catch
      nothing
    end
    if unit_ isa Unitful.Units
      quantity = parse(Float64, m.captures[1]) * unit_
    end
  end
  if isnothing(quantity)
    throw(ScannerConfigurationError("The frequency key `$key` of the transfer function could not be parsed. Give a number in Hz (e.g. \"25000\") or a number with a frequency unit (e.g. \"25kHz\")."))
  elseif dimension(quantity) != dimension(u"Hz")
    throw(ScannerConfigurationError("The frequency key `$key` of the transfer function does not have a frequency unit."))
  elseif !is_hz_based(unit(quantity))
    throw(ScannerConfigurationError("The frequency key `$key` of the transfer function has the unit `$(unit(quantity))`. Frequencies must be given in Hz-based units (e.g. \"25kHz\") or in s^-1, not as angular frequency (e.g. rad/s, °/s or rpm)."))
  end
  return ustrip(u"Hz", quantity)
end

# Unitful treats rad and ° as dimensionless and defines rps/rpm via 2π rad, so an angular
# frequency has the dimension of a frequency but converts to Hz without the factor 2π.
# Only units built from Hz and s (with any prefix) are therefore accepted.
is_hz_based(u::Unitful.Units) = all(f -> Unitful.name(f) in (:Hertz, :Second), typeof(u).parameters[1])

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