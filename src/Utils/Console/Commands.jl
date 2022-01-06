# list scanners
# list protocols
# list sequences
# list devices
# start
# stop
# pause
# set experiment
# set study
# show 

function list_scanners()
  scannerNames::Vector{String} = []
  for configDir in scannerConfigurationPath
    dirs = filter(x -> isdir(joinpath(configDir, x)), readdir(configDir))
    scannerNames = vcat(scannerNames, dirs)
  end

  return scannerNames
end

function mpi_mode_activate(;scannerName_::Union{String, Nothing} = nothing)
  if isnothing(mpi_repl_mode.activeProtocolHandler)
    if isnothing(scannerName_)
      settingspath = abspath(homedir(), ".mpi")
      settingsfile = joinpath(settingspath, "Settings.toml")
      if isfile(settingsfile)
        settings = TOML.parsefile(settingsfile)
        scannerName_ = settings["scanner"]
      else
        options = list_scanners()
        menu = REPL.TerminalMenus.RadioMenu(options, pagesize=4)
        choice = REPL.TerminalMenus.request("Choose scanner:", menu)

        if choice != -1
          scannerName_ = options[choice]
        else
          println("Scanner selection canceled.")
        end
      end
    end

    println("Activating scanner `$scannerName_`.")
    global mpi_repl_mode.activeProtocolHandler = ConsoleProtocolHandler(scannerName_)
  else
    println("A scanner has already been activated. Please deactivate first.")
    # Handle shutdown of old protocol handler
  end

  return
end

# function mpi_mode_add_configuration(path::String)
#   @warn "add scanner configuration folder scanners: $path"
# end

mpi_repl_mode.commands["activate"] = CommandSpec(
  canonical_name = "activate",
  short_name = "act",
  api = mpi_mode_activate,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :scannerName_,
    ),
  ),
  completions = nothing,
  description = "Activate a specific scanner or select from a list"
)

function mpi_mode_deactivate()
  if !isnothing(mpi_repl_mode.activeProtocolHandler)
    println("Deactivating `$(scannerName(mpi_repl_mode.activeProtocolHandler.scanner))`.")
    if !isnothing(MPIMeasurements.mpi_repl_mode.activeProtocolHandler.biChannel)
      endProtocol(mpi_repl_mode.activeProtocolHandler)
    end
    mpi_repl_mode.activeProtocolHandler = nothing
  else
    println("No scanner active and thus nothing is done.")
  end
end

mpi_repl_mode.commands["deactivate"] = CommandSpec(
  canonical_name = "deactivate",
  short_name = "deact",
  api = mpi_mode_deactivate,
  description = "Dectivate current scanner."
)

# Base.@kwdef struct CommandSpec
#   canonical_name::String
#   short_name::Union{Nothing, String} = nothing
#   api::Function
#   option_specs::Dict{String, OptionSpec}
#   completions::Union{Nothing, Function} = nothing
#   description::String
#   #help::Union{Nothing,Markdown.MD}
# end

# Base.@kwdef struct OptionSpec
#   name::String
#   short_name::Union{Nothing,String} = nothing
#   api::Pair{Symbol, Any}
#   takes_arg::Bool = false
# end