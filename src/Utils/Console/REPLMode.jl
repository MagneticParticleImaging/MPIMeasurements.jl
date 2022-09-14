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

function Base.close(mpiMode::MPIREPLMode)
  if !isnothing(mpiMode.activeProtocolHandler)
    close(mpiMode.activeProtocolHandler)
  end
end

mpi_repl_mode = MPIREPLMode()

export getLastMeasData
getLastMeasData() = getMeasurements(mpi_repl_mode.activeProtocolHandler.lastSavedFile)

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
        args = Dict{Symbol, Any}()
        cmdArgs = splittedCommand[2:end]
        parse_options!(args, spec.option_specs, cmdArgs)
        if isempty(args)
          args[spec.option_specs["default"].api] = join(cmdArgs, " ")
        end
        spec.api(;args...)
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

function parse_options!(args::Dict{Symbol, Any}, option_specs::Dict{String, OptionSpec}, cmdArgs::Vector{String})
  # Assumption: Parameter have an arity of one: param value param value ...
  # Otherwise need to add arity information
  for i = 1:Int64(div(length(cmdArgs), 2))
    if haskey(option_specs, cmdArgs[(2*i)-1])
      args[option_specs[cmdArgs[(2*i) -1]].api] = cmdArgs[2*i]
    end
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
  if isdefined(Base, :active_repl)
    initrepl(parse_command,
            prompt_text=prompt_string,
            start_key='|',
            repl = Base.active_repl,
            mode_name="MPI mode",
            valid_input_checker=mpi_mode_valid_input_checker,
            completion_provider=MPICompletionProvider(),
            startup_text=false)
  end
end