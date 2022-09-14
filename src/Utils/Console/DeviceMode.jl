struct DeviceCommand
  name::String
  fun::Function
  args::Vector{Tuple{Symbol, Type}}
  kwargs::Vector{Tuple{Symbol, Type}}
end

Base.@kwdef mutable struct DeviceREPLMode
  activeDeviceID::Union{String, Nothing} = nothing
  commands::Vector{CommandSpec} = Vector{CommandSpec}()
  deviceCommands::Dict{DataType, Vector{DeviceCommand}} = Dict{DataType, Vector{DeviceCommand}}()
end

function Base.close(deviceMode::DeviceREPLMode)
  deviceMode.activeDeviceID = nothing
end

device_repl_mode = DeviceREPLMode()

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
  
  if !(deviceType <: Device)
    error("The type of the device has to be a subtype of `Device`.")
  end

  # The rest of them
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

  #body = splitted[:body]

  if !haskey(device_repl_mode.deviceCommands, deviceType)
    device_repl_mode.deviceCommands[deviceType] = []
  end

  # Mangle the function name in order to not interfere with device functions named in the same way
  mangledName = Symbol(:device_repl_mode_function_, name)
  splitted[:name] = mangledName

  # Evaluate function to be able to eval the name
  eval(combinedef(splitted))

  functionHandle = eval(mangledName)
  if isexpr(functionHandle) || !(typeof(functionHandle) <: Function)
    error("The symbol `$name` should refer to a function. Is it defined as a global variable?")
  end
  push!(device_repl_mode.deviceCommands[deviceType], DeviceCommand(String(name), functionHandle, argsResult, kwargsResult)) # TODO: Check if another command with the same name and total number of arguments already exists

  return nothing
end

include("DeviceCommands.jl")

default_device_commands() = [command.canonical_name for command in device_repl_mode.commands]

function extended_device_commands()
  canonicalNames = device_commands()

  synonyms = []
  for command in device_repl_mode.commands
    if !isnothing(command.synonyms)
      append!(synonyms, command.synonyms)
    end
  end

  return vcat(canonicalNames, synonyms)
end

function device_commands()
  if !isnothing(device_repl_mode.activeDeviceID)
    commands = default_device_commands()
    device = getDevice(mpi_repl_mode.activeProtocolHandler.scanner, device_repl_mode.activeDeviceID)

    # Iterate supertypes except for the type itself and Any
    for type in supertypes(typeof(device))[2:end-1]
      deviceCommands = get(device_repl_mode.deviceCommands, type, nothing)
      if !isnothing(deviceCommands)
        append!(commands, [command.name for command in deviceCommands])
      end
    end

    return commands
  else
    return default_device_commands()
  end
end

function get_device_command(command::String)
  # Check for non-device-specific commands first
  for command_ in device_repl_mode.commands
    if command_.canonical_name == command || command_.short_name == command
      return command_
    end

    if !isnothing(command_.synonyms) && command in command_.synonyms
      return command_
    end
  end

  # ... then check device-specific commands (iterate supertypes except for the type itself and Any)
  if !isnothing(device_repl_mode.activeDeviceID)
    device = getDevice(mpi_repl_mode.activeProtocolHandler.scanner, device_repl_mode.activeDeviceID)
    matchingCommands = Vector{DeviceCommand}()
    for type in supertypes(typeof(device))[2:end-1]
      deviceCommands = get(device_repl_mode.deviceCommands, type, nothing)
      if !isnothing(deviceCommands)
        append!(matchingCommands, [command_ for command_ in deviceCommands if command_.name == command])
      end
    end

    if length(matchingCommands) > 0
      return matchingCommands
    end
  end

  return nothing
end

function parse_device_command(command::String)
  splittedCommandUnparsed = [elem for elem in flatten(split.(split(command, "[", keepempty=false), "]", keepempty=false))]
  splittedCommandUnparsed = convert.(String, splittedCommandUnparsed)
  splittedCommand = convert(Vector{Any}, convert.(String, split(splittedCommandUnparsed[1], " ", keepempty=false)))
  
  for elem in splittedCommandUnparsed[2:end]
    tmpSplit = split(elem, ", ")
    tmpSplit = collect(flatten(split.(tmpSplit, ",", keepempty=false)))
    push!(splittedCommand, tryuparse.(tmpSplit))
  end

  spec = get_device_command(String(splittedCommand[1]))

  if !isnothing(spec)
    if eltype(spec) == DeviceCommand
      # Select command depending on number of arguments
      selectedCommand = [command_ for command_ in spec if length(command_.args)+length(command_.kwargs) == length(splittedCommand)-1]
      selectedCommand = length(selectedCommand) > 0 ? selectedCommand[1] : nothing

      if isnothing(selectedCommand)
        println("No matching command definition for the given amount of arguments can be found.")
      else
        activeDevice = getDevice(mpi_repl_mode.activeProtocolHandler.scanner, device_repl_mode.activeDeviceID)
        selectedCommand.fun(activeDevice, Tuple(splittedCommand[2:end])...)
      end
    elseif typeof(spec) == CommandSpec
      if length(splittedCommand) > 1
        if !isnothing(spec.option_specs)
          if haskey(spec.option_specs, splittedCommand[2])
            spec.api(;Dict{Symbol, Any}(spec.option_specs[splittedCommand[2]].api => splittedCommand[3])...)
          else
            spec.api(;Dict{Symbol, Any}(spec.option_specs["default"].api => splittedCommand[2])...)
          end
        else
          println("No additional parameters allowed for command `$(spec.canonical_name)`.")
        end
      else
        spec.api()
      end
    else
      # NOP
      #@warn "None of the two possible types matched. Element type is `$(eltype(spec))`."
    end
  else
    print("Command `$(splittedCommand[1])` cannot be found.")
  end
end

function prompt_string_device()
  if !isnothing(device_repl_mode.activeDeviceID)
    result = "DEV ($(device_repl_mode.activeDeviceID))> "
  else
    result = "DEV> "
  end

  return result
end


# Adapted from https://github.com/JuliaLang/Pkg.jl

struct DeviceCompletionProvider <: LineEdit.CompletionProvider end

function LineEdit.complete_line(c::DeviceCompletionProvider, s)
    partial = REPL.beforecursor(s.input_buffer)
    full = LineEdit.input_string(s)
    ret, range, should_complete = completionsDevice(full, lastindex(partial))
    return ret, partial[range], should_complete
end

function completionsDevice(full, index)::Tuple{Vector{String},UnitRange{Int},Bool}
  pre = full[1:index]
  isempty(pre) && return device_commands(), 0:-1, false # empty input -> complete commands
  offset_adjust = 0
  if length(pre) >= 2 && pre[1] == '?' && pre[2] != ' '
      # supports completion on things like `DEV> ?act` with no space
      pre = string(pre[1], " ", pre[2:end])
      offset_adjust = -1
  end
  last = split(pre, ' ', keepempty=true)[end]
  offset = isempty(last) ? index+1+offset_adjust : last.offset+1+offset_adjust
  final  = isempty(last) # is the cursor still attached to the final token?
  return _completionsDevice(pre, final, offset, index)
end

function _completionsDevice(input, final, offset, index)
  splittedCommand = convert(Vector{String}, split(input, " "))

  if length(splittedCommand) > 1
    command_ = get_device_command(splittedCommand[1])

    if isnothing(command_.completions)
      possible = []
    else
      possible = command_.completions(join(splittedCommand[2:end], " "), final, offset, index)
    end
  else
    possible = [command for command in extended_device_commands() if startswith(command, input)]
  end
  
  return possible, offset:index, !isempty(possible)
end

function device_mode_valid_input_checker(input)
  #@info input
  return true
end

export device_mode_enable
function device_mode_enable()
  if isdefined(Base, :active_repl)
    initrepl(parse_device_command,
            prompt_text=prompt_string_device,
            start_key="\\M-m",
            repl = Base.active_repl,
            mode_name="Device mode",
            valid_input_checker=device_mode_valid_input_checker,
            completion_provider=DeviceCompletionProvider(),
            startup_text=false)
  end
end