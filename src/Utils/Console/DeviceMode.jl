Base.@kwdef mutable struct DeviceREPLMode
  activeDeviceID::Union{String, Nothing} = nothing
  commands::Vector{CommandSpec} = Vector{CommandSpec}()
end

function Base.close(deviceMode::DeviceREPLMode)
  deviceMode.activeDeviceID = nothing
end

device_repl_mode = DeviceREPLMode()

include("DeviceCommands.jl")

default_device_commands() = [command.canonical_name for command in device_repl_mode.commands]

function extended_device_commands()
  canonicalNames = default_device_commands()

  synonyms = []
  for command in device_repl_mode.commands
    if !isnothing(command.synonyms)
      append!(synonyms, command.synonyms)
    end
  end

  return vcat(canonicalNames, synonyms)
end

function get_device_command(command::String)
  for command_ in device_repl_mode.commands
    if command_.canonical_name == command || command_.short_name == command
      return command_
    end

    if !isnothing(command_.synonyms) && command in command_.synonyms
      return command_
    end
  end

  return nothing
end

function parse_device_command(command::String)
  splittedCommand = convert(Vector{String}, split(command, " "))

  spec = get_device_command(splittedCommand[1])

  if !isnothing(spec)
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
  isempty(pre) && return default_device_commands(), 0:-1, false # empty input -> complete commands
  offset_adjust = 0
  if length(pre) >= 2 && pre[1] == '?' && pre[2] != ' '
      # supports completion on things like `MPI> ?act` with no space
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