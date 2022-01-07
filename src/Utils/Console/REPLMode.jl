# Adapted from https://github.com/JuliaLang/Pkg.jl
Base.@kwdef struct OptionSpec
  name::String
  short_name::Union{String, Nothing} = nothing
  api::Symbol
  takes_arg::Bool = false
end

Base.@kwdef struct CommandSpec
  canonical_name::String
  short_name::Union{String, Nothing} = nothing
  synonyms::Union{Vector{String}, Nothing} = nothing
  api::Function
  option_specs::Union{Dict{String, OptionSpec}, Nothing} = nothing
  completions::Union{Function, Nothing} = nothing
  description::String
  #help::Union{Nothing,Markdown.MD}
end

Base.@kwdef mutable struct MPIREPLMode
  activeProtocolHandler::Union{ConsoleProtocolHandler, Nothing} = nothing
  commands::Vector{CommandSpec} = Vector{CommandSpec}()
end

mpi_repl_mode = MPIREPLMode()

include("Commands.jl")

default_commands() = [command.canonical_name for command in mpi_repl_mode.commands]

function extended_commands()
  canonicalNames = default_commands()

  synonyms = []
  for command in mpi_repl_mode.commands
    if !isnothing(command.synonyms)
      append!(synonyms, command.synonyms)
    end
  end

  return vcat(canonicalNames, synonyms)
end

function get_command(command::String)
  for command_ in mpi_repl_mode.commands
    if command_.canonical_name == command || command_.short_name == command
      return command_
    end

    if !isnothing(command_.synonyms) && command in command_.synonyms
      return command_
    end
  end

  return nothing
end

function parse_command(command::String)
  splittedCommand = convert(Vector{String}, split(command, " "))

  spec = get_command(splittedCommand[1])

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

function prompt_string()
  if !isnothing(mpi_repl_mode.activeProtocolHandler)
    result = "MPI ($(scannerName(mpi_repl_mode.activeProtocolHandler.scanner)))> "
  else
    result = "MPI> "
  end

  return result
end

# Adapted from https://github.com/JuliaLang/Pkg.jl

struct MPICompletionProvider <: LineEdit.CompletionProvider end

function LineEdit.complete_line(c::MPICompletionProvider, s)
    partial = REPL.beforecursor(s.input_buffer)
    full = LineEdit.input_string(s)
    ret, range, should_complete = completions(full, lastindex(partial))
    return ret, partial[range], should_complete
end

function completions(full, index)::Tuple{Vector{String},UnitRange{Int},Bool}
  pre = full[1:index]
  isempty(pre) && return default_commands(), 0:-1, false # empty input -> complete commands
  offset_adjust = 0
  if length(pre) >= 2 && pre[1] == '?' && pre[2] != ' '
      # supports completion on things like `MPI> ?act` with no space
      pre = string(pre[1], " ", pre[2:end])
      offset_adjust = -1
  end
  last = split(pre, ' ', keepempty=true)[end]
  offset = isempty(last) ? index+1+offset_adjust : last.offset+1+offset_adjust
  final  = isempty(last) # is the cursor still attached to the final token?
  return _completions(pre, final, offset, index)
end

function _completions(input, final, offset, index)
  splittedCommand = convert(Vector{String}, split(input, " "))

  if length(splittedCommand) > 1
    command_ = get_command(splittedCommand[1])

    if isnothing(command_.completions)
      possible = []
    else
      possible = command_.completions(join(splittedCommand[2:end], " "), final, offset, index)
    end
  else
    possible = [command for command in extended_commands() if startswith(command, input)]
  end
  
  return possible, offset:index, !isempty(possible)
end

function mpi_mode_valid_input_checker(input)
  #@info input
  return true
end

export mpi_mode_enable
function mpi_mode_enable()
  initrepl(parse_command, 
           prompt_text=prompt_string,
           start_key='|', 
           mode_name="MPI mode",
           valid_input_checker=mpi_mode_valid_input_checker,
           completion_provider=MPICompletionProvider(),
           startup_text=false)
end