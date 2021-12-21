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
  api::Function
  option_specs::Union{Dict{String, OptionSpec}, Nothing} = nothing
  completions::Union{Function, Nothing} = nothing
  description::String
  #help::Union{Nothing,Markdown.MD}
end

Base.@kwdef mutable struct MPIREPLMode
  activeProtocolHandler::Union{ConsoleProtocolHandler, Nothing} = nothing
  commands::Dict{String, CommandSpec} = Dict{String, CommandSpec}()
end

mpi_repl_mode = MPIREPLMode()

include("Commands.jl")

default_commands() = keys(commands)

function parse_command(command::String)
  splittedCommand = convert(Vector{String}, split(command, " "))
  if haskey(mpi_repl_mode.commands, splittedCommand[1])
    spec = mpi_repl_mode.commands[splittedCommand[1]]

    if length(splittedCommand) > 1
      if haskey(spec.option_specs, splittedCommand[2])
        spec.api(;Dict{Symbol, Any}(spec.option_specs[splittedCommand[2]].api => splittedCommand[3])...)
      else
        spec.api(;Dict{Symbol, Any}(spec.option_specs["default"].api => splittedCommand[2])...)
      end
    else
      spec.api()
    end
  else
    print("Command `$(splittedInstruction[1])` cannot be found.")
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
  @info "" input, final, offset, index

  possible = ["activate", "list"]

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