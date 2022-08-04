using MacroTools

mutable struct Scanner
end

abstract type Device end

mutable struct TestDevice <: Device
  testField::String
end

mutable struct TestDevice2 <: Device
  testField::String
end

dev = TestDevice("Test")
scanner = Scanner()

struct Command
  fun::Function
  args::Vector{Tuple{Symbol, Type}}
  kwargs::Vector{Tuple{Symbol, Type}}
end

commands = Dict{DataType, Vector{Command}}()

macro devicecommand(expr)
  splitted = splitdef(expr)
  name = splitted[:name]
  args = splitted[:args]
  kwargs = splitted[:kwargs]

  # The first arg must be the device
  typeOfFirst = args[1].args[2]
  if isexpr(typeOfFirst)
    error("The macro does not support composite types like unions.")
  end
  deviceType = eval(typeOfFirst)
  deviceVarname = args[1].args[1]
  
  if !(deviceType <: Device)
    error("The type of the device has to be a subtype of `Device`.")
  end

  # The rest of them are common args
  argsResult = Vector{Tuple{Symbol, Type}}()
  for arg in args[2:end]
    if isexpr(arg.args[1])
      varname = arg.args[1].args[1]
      type = eval(arg.args[1].args[2])
    else
      varname = arg.args[1]
      type = eval(arg.args[2])
    end
    push!(argsResult, (varname, type))
  end

  kwargsResult = Vector{Tuple{Symbol, Type}}()
  for kwarg in kwargs
    #@info kwarg
    varname = kwarg.args[1].args[1]
    type = eval(kwarg.args[1].args[2])
    push!(kwargsResult, (varname, type))
  end

  if splitted[:whereparams] != ()
    error("The macro does not support where params.")
  end

  if !haskey(commands, deviceType)
    commands[deviceType] = []
  end

  # Rewrite function to work on scanner and retrieve device under the given name
  body = splitted[:body]
  @info body

  # Evaluate function to be able to eval the name
  eval(combinedef(splitted))

  functionHandle = eval(name)
  if isexpr(functionHandle) || !(typeof(functionHandle) <: Function)
    error("The symbol `$name` should refer to a function. Is it defined as a global variable?")
  end
  push!(commands[deviceType], Command(functionHandle, argsResult, kwargsResult))

  return nothing
end

@devicecommand function update(dev::TestDevice, tag::String; test::String="test")
  return nothing
end

@devicecommand function test(dev::TestDevice, tag::String; test::String="test")
  return nothing
end

@devicecommand function test(dev::TestDevice2, tag::String; test::String="test")
  return nothing
end

@devicecommand test2(dev::TestDevice2, tag::String; test::String="test") = nothing

@devicecommand function test3(dev::TestDevice2, tag::String, test2::Array=[]; test::String="test")
  return nothing
end