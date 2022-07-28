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

function check_no_scanner()
  if !isnothing(mpi_repl_mode.activeProtocolHandler)
    return true
  else
    println("There is currently no scanner selected. Please activate one using `activate`.")
    return false
  end
end


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
          return
        end
      end
    else
      if !(scannerName_ in list_scanners())
        println("The selected scanner `$scannerName_` is not in the list of available scanners. ")
        println("If you think this is a mistake, please check the following list of configuration "*
                "directories and add the necessary directory if necessary.")
        println("")
        println("Available configuration directories:")

        for configDir_ in scannerConfigurationPath
          println("- $configDir_")
        end

        return
      end
    end

    println("Activating scanner `$scannerName_`.")
    global mpi_repl_mode.activeProtocolHandler = ConsoleProtocolHandler(scannerName_)
  else
    println("A scanner has already been activated. Please deactivate first.")
  end

  return
end

# function mpi_mode_add_configuration(path::String)
#   @warn "add scanner configuration folder scanners: $path"
# end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "activate",
  short_name = "ac",
  api = mpi_mode_activate,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :scannerName_,
    ),
  ),
  completions = (input, final, offset, index) -> begin
    # In case of an empty input, return the default if available
    if input == ""
      settingspath = abspath(homedir(), ".mpi")
      settingsfile = joinpath(settingspath, "Settings.toml")
      if isfile(settingsfile)
        settings = TOML.parsefile(settingsfile)
        scannerName_ = settings["scanner"]
        return [scannerName_]
      else
        return []
      end
    else
      return [scanner_ for scanner_ in list_scanners() if startswith(scanner_, input)]
    end
  end,
  description = "Activate a specific scanner or select from a list"
))

function mpi_mode_deactivate()
  if !isnothing(mpi_repl_mode.activeProtocolHandler)
    println("Deactivating `$(scannerName(mpi_repl_mode.activeProtocolHandler.scanner))`.")
    if !isnothing(MPIMeasurements.mpi_repl_mode.activeProtocolHandler.biChannel)
      endProtocol(mpi_repl_mode.activeProtocolHandler)
    end
    close(mpi_repl_mode.activeProtocolHandler)
    mpi_repl_mode.activeProtocolHandler = nothing
  else
    println("No scanner active and thus nothing is done.")
  end
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "deactivate",
  short_name = "deac",
  api = mpi_mode_deactivate,
  description = "Dectivate current scanner."
))

function mpi_mode_attach(scanner::MPIScanner)
  mpi_repl_mode.activeProtocolHandler = ConsoleProtocolHandler(scanner)
end

function mpi_mode_attach(;variable::String)
  sym = Symbol(variable)
  mpi_mode_attach(Main.eval(sym))
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "attach",
  short_name = "att",
  api = mpi_mode_attach,
  description = "Attach to a given scanner.",
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :variable,
    ),
  )
))

function mpi_mode_detach()
  temp = mpi_repl_mode.activeProtocolHandler 
  mpi_repl_mode.activeProtocolHandler = nothing
  return temp
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "detach",
  short_name = "detach",
  api = mpi_mode_detach,
  description = "Detach the current scanner.",
))

function mpi_mode_device(device::String)
  return getDevice(mpi_repl_mode.activeProtocolHandler.scanner, device)
end

function mpi_mode_device(device::Nothing)
  device = ""
  options = deviceID.(getDevices(mpi_repl_mode.activeProtocolHandler.scanner, Device))
  menu = REPL.TerminalMenus.RadioMenu(options, pagesize=8)
  choice = REPL.TerminalMenus.request("Choose device:", menu)
  if choice != -1
    device = options[choice]
  else
    println("Device selection canceled.")
    return
  end
  return mpi_mode_device(device)
end

function mpi_mode_protocol(protocol::String)
  return Protocol(protocol, mpi_repl_mode.activeProtocolHandler.scanner)
end

function mpi_mode_protocol(protocol::Nothing)
  protocol = ""
  options = getProtocolList(mpi_repl_mode.activeProtocolHandler.scanner)
  menu = REPL.TerminalMenus.RadioMenu(options, pagesize=8)
  choice = REPL.TerminalMenus.request("Choose protocol:", menu)
  if choice != -1
    protocol = options[choice]
  else
    println("Protocol selection canceled.")
    return
  end
  return mpi_mode_protocol(protocol)
end

function mpi_mode_sequence(sequence::String)
  return Sequence(mpi_repl_mode.activeProtocolHandler.scanner, sequence)
end

function mpi_mode_sequence(sequence::Nothing)
  seq = ""
  options = getSequenceList(mpi_repl_mode.activeProtocolHandler.scanner)
  menu = REPL.TerminalMenus.RadioMenu(options, pagesize=8)
  choice = REPL.TerminalMenus.request("Choose sequence:", menu)
  if choice != -1
    seq = options[choice]
  else
    println("Sequence selection canceled.")
    return
  end
  return mpi_mode_sequence(seq)
end

function mpi_mode_get(;getter::String)
  if !isnothing(mpi_repl_mode.activeProtocolHandler)
    parts = split(getter, " ")
    type = parts[1]
    value = nothing
    if length(parts) > 1
      value = String(parts[2])
    end
    if lowercase(type) == "device"
      return mpi_mode_device(value)
    elseif lowercase(type) == "protocol"
      return mpi_mode_protocol(value)
    elseif lowercase(type) == "params"
      return mpi_repl_mode.activeProtocolHandler.protocol.params
    elseif lowercase(type) == "sequence"
      return mpi_mode_sequence(value)
    elseif lowercase(type) == "scanner"
      return mpi_repl_mode.activeProtocolHandler.scanner
    else
      println("Unknown option: $type")
      return nothing
    end
  else
    println("No attached scanner")
    return nothing
  end
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "get",
  short_name = "get",
  api = mpi_mode_get,
  description = "Get a device, protocol, protocol parameter, sequence of the attached scanner or the scanner itself. Access value with 'ans' afterwards",
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :getter,
    ),
  )
))

function check_protocol_available(protocolName_::String)
  if !(protocolName_ in getProtocolList(mpi_repl_mode.activeProtocolHandler.scanner))
    println("The selected protocol `$protocolName_` is not available. Please check the spelling or use `init` without an argument to select from a list.")
    return false
  else
    return true
  end
end

function mpi_mode_init_protocol(;protocolName_::Union{String, Nothing} = nothing)
  if isnothing(mpi_repl_mode.activeProtocolHandler)
    println("There is currently no scanner selected. Please activate one using `activate`.")
    return
  end

  if isnothing(mpi_repl_mode.activeProtocolHandler.protocol)
    if isnothing(protocolName_)
      defaultOption = defaultProtocol(mpi_repl_mode.activeProtocolHandler.scanner)
      options = getProtocolList(mpi_repl_mode.activeProtocolHandler.scanner)
      menu = REPL.TerminalMenus.RadioMenu(options, pagesize=4)
      defaultOptionIdx = findall(x->x==defaultOption, options)[1]
      choice = REPL.TerminalMenus.request("Choose protocol:", menu, cursor=defaultOptionIdx)

      if choice != -1
        protocolName_ = options[choice]
      else
        println("Protocol selection canceled.")
        return
      end
    else
      if !check_protocol_available(protocolName_)
        return
      end
    end
  else
    currProtocolName = name(mpi_repl_mode.activeProtocolHandler.protocol)

    if currProtocolName == protocolName_
      println("The current protocol already is `$currProtocolName`. Nothing is changed.")
      return
    else
      menu = REPL.TerminalMenus.RadioMenu(["Yes", "No"], pagesize=4)
      choice = REPL.TerminalMenus.request("The current protocol is `$currProtocolName`. Do you want to stop the current one and change to `$protocolName_`?", menu, cursor=2)

      if choice == 1
        global mpi_repl_mode.activeProtocolHandler.protocol = nothing
        mpi_mode_init_protocol(protocolName_=protocolName_)
        return
      else
        println("Protocol selection canceled.")
        return
      end
    end
  end

  if check_protocol_available(protocolName_)
    println("Initializing protocol `$protocolName_`.")
    global mpi_repl_mode.activeProtocolHandler.protocol = Protocol(protocolName_, mpi_repl_mode.activeProtocolHandler.scanner)
    initProtocol(mpi_repl_mode.activeProtocolHandler)
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "init",
  api = mpi_mode_init_protocol,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :protocolName_,
    ),
  ),
  completions = (input, final, offset, index) -> begin  
    # Prevent errors with non-activated scanner
    if isnothing(mpi_repl_mode.activeProtocolHandler) || isnothing(mpi_repl_mode.activeProtocolHandler.scanner)
      return []
    end

    if input == ""
      return [defaultProtocol(mpi_repl_mode.activeProtocolHandler.scanner)]
    else
      return [protocol_ for protocol_ in getProtocolList(mpi_repl_mode.activeProtocolHandler.scanner) if startswith(protocol_, input)]
    end
  end,
  description = "Init protocol."
))

function mpi_mode_start_protocol()
  if check_no_scanner()
    startProtocol(mpi_repl_mode.activeProtocolHandler)
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "start",
  api = mpi_mode_start_protocol,
  description = "Start protocol."
))

function mpi_mode_end_protocol()
  if check_no_scanner()
    endProtocol(mpi_repl_mode.activeProtocolHandler)
  end
  
  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "end",
  synonyms = ["stop"],
  api = mpi_mode_end_protocol,
  description = "End protocol."
))

# Storage commands

function mpi_mode_study()
  if check_no_scanner()
    if isnothing(study(mpi_repl_mode.activeProtocolHandler))
      study(mpi_repl_mode.activeProtocolHandler, MDFv2Study()) # TODO: Auto-generate fields
    end
    study_ = study(mpi_repl_mode.activeProtocolHandler)

    options = ["Name: $(studyName(study_))", "Description: $(studyDescription(study_))"]
    optionFields = ["name", "description"]
    menu = TerminalMenus.RadioMenu(options, pagesize=4)

    choice = TerminalMenus.request("Select field to edit (exit with `q`):", menu)

    if choice != -1
      println("Please enter the new value for the field `$(optionFields[choice])` (press `↵` to confirm; if nothing is entered, the old value is kept): ")
      value = readline()
      if value == ""
        println("The old $(optionFields[choice]) of the study was kept.")
        return
      end

      if optionFields[choice] == "name"
        studyName(study_, value)
        println("The name of the study was set to `$value`.")
      elseif optionFields[choice] == "description"
        studyDescription(study_, value)
        println("The description of the study was set to `$value`.")
      else
        @error "No valid selection. Please check the code."
      end
    end
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "study",
  api = mpi_mode_study,
  description = "Show and set study parameters."
))

function mpi_mode_experiment()
  if check_no_scanner()
    if isnothing(experiment(mpi_repl_mode.activeProtocolHandler))
      experiment(mpi_repl_mode.activeProtocolHandler, MDFv2Experiment()) # TODO: Auto-generate fields
    end
    experiment_ = experiment(mpi_repl_mode.activeProtocolHandler)

    options = ["Name: $(experimentName(experiment_))", "Description: $(experimentDescription(experiment_))", "Subject: $(experimentSubject(experiment_))"]
    optionFields = ["name", "description", "subject"]
    menu = TerminalMenus.RadioMenu(options, pagesize=4)

    choice = TerminalMenus.request("Select field to edit (exit with `q`):", menu)

    if choice != -1
      println("Please enter the new value for the field `$(optionFields[choice])` (press `↵` to confirm; if nothing is entered, the old value is kept): ")
      value = readline()
      if value == ""
        println("The old $(optionFields[choice]) of the study was kept.")
        return
      end

      if optionFields[choice] == "name"
        experimentName(experiment_, value)
        println("The name of the experiment was set to `$value`.")
      elseif optionFields[choice] == "description"
        experimentDescription(experiment_, value)
        println("The description of the experiment was set to `$value`.")
      elseif optionFields[choice] == "subject"
        experimentSubject(experiment_, value)
        println("The subject of the experiment was set to `$value`.")
      else
        @error "No valid selection. Please check the code."
      end
    end
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "experiment",
  api = mpi_mode_experiment,
  description = "Show and set experiment parameters."
))

function mpi_mode_tracer(;mode::Union{String, Nothing} = nothing)
  if check_no_scanner()
    if isnothing(tracer(mpi_repl_mode.activeProtocolHandler))
      tracer(mpi_repl_mode.activeProtocolHandler, MDFv2Tracer()) # TODO: Auto-generate fields
    end
    tracers = tracer(mpi_repl_mode.activeProtocolHandler)

    if isnothing(mode) || mode == "list"
      if !ismissing(tracerName(tracers))
        for (index, tracerName_) in enumerate(tracerName(tracers))
          println("Tracer $index:")
          println("Name           | $(tracerName(tracers)[index])")
          println("Batch          | $(tracerBatch(tracers)[index])")
          println("Concentration  | $(tracerConcentration(tracers)[index])")
          println("Injection time | $(tracerInjectionTime(tracers)[index])")
          println("Solute         | $(tracerSolute(tracers)[index])")
          println("Vendor         | $(tracerVendor(tracers)[index])")
          println("Volume         | $(tracerVolume(tracers)[index])")
          println("")
        end
      else
        println("There are currently no tracers set.")
      end
    elseif mode == "add"
      println("Please enter the name:")
      name = readline()

      println("Please enter the batch:")
      batch = readline()

      println("Please enter the molar concentration of solute per litre:")
      concentration = nothing
      while true
        concentration = tryparse(Float64, readline())
        if isnothing(concentration)
          println("The given value `$concentration` could not be parsed to a floating point number.")
        else
          break
        end
      end

      println("Please enter the UTC time at which tracer injection started in the format `yyyy-mm-dd HH:MM:SS` (leave blank to use current time):")
      injectionTime = readline()
      if injectionTime == ""
        injectionTime = now()
      else
        injectionTime = DateTime(injectionTime, "yyyy-mm-dd HH:MM:SS")
      end

      println("Please enter the solute (leave blank to use `Fe`):")
      solute = readline()
      if injectionTime == ""
        solute = "Fe"
      end

      println("Please enter the vendor:")
      vendor = readline()

      println("Please enter the volume:")
      volume  = nothing
      while true
        volume = tryparse(Float64, readline())
        if isnothing(volume)
          println("The given value `$volume` could not be parsed to a floating point number.")
        else
          break
        end
      end

      addTracer(tracers; batch, concentration, injectionTime, name, solute, vendor, volume)
    elseif mode == "remove"
      @error "Not yet supported."
    else
      println("Unknown mode `$mode`. Please use one of the following: `add`, `remove` or `list`.")
    end
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "tracer",
  api = mpi_mode_tracer,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :mode,
    ),
  ),
  completions = (input, final, offset, index) -> begin  
    # Prevent errors with non-activated scanner
    if isnothing(mpi_repl_mode.activeProtocolHandler) || isnothing(mpi_repl_mode.activeProtocolHandler.scanner)
      return []
    end

    modes = ["add", "remove", "list"]

    if input == ""
      return modes
    else
      return [mode for mode in modes if startswith(mode, input)]
    end
  end,
  description = "Show and set tracer parameters."
))

function mpi_mode_operator(;operator_::Union{String, Nothing} = nothing)
  if isnothing(operator_)
    println("Operator: $(mpi_repl_mode.activeProtocolHandler.currOperator)")
  else
    operator(mpi_repl_mode.activeProtocolHandler, operator_)
    println("The new operator is `$operator_`.")
  end

  return
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "operator",
  api = mpi_mode_operator,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :operator_,
    ),
  ),
  description = "Show and set operator."
))

# Auxiliary commands
function mpi_mode_debug(debug::Bool)
  if debug
    ENV["JULIA_DEBUG"] = "all"
    println("Debug mode activated.")
  else
    ENV["JULIA_DEBUG"] = ""
    println("Debug mode deactivated.")
  end
end
function mpi_mode_debug(;debug_flag::String = "")
  debug = false
  if debug_flag == ""
    if haskey(ENV, "JULIA_DEBUG")
      debug = !(ENV["JULIA_DEBUG"] == "all")
    else
      debug = true
    end
  else
    debug = parse(Bool, debug_flag)
  end
  mpi_mode_debug(debug)
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "debug",
  api = mpi_mode_debug,
  description = "Enable/disable to debug mode.",
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :debug_flag,
    ),
  )
))

function mpi_mode_exit()
  Base.exit()
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "exit",
  synonyms = ["exit()"],
  api = mpi_mode_exit,
  description = "Exit Julia."
))

function mpi_mode_help(cmd::String)
  command = get_command(cmd)
  if isnothing(command)
    println("Unknown command: $cmd")
  else
    names = filter(!isnothing, vcat(command.short_name, command.synonyms))
    options = ""
    if !isempty(names)
      synonyms = join(names, ", ", " and ")
      options = " (or " * synonyms * ")"
    end
    println(command.canonical_name*options*":")
    println(command.description)
  end
end

function mpi_mode_help(;cmd::String="")
  if cmd == ""
    for command in mpi_repl_mode.commands
      mpi_mode_help(command.canonical_name)
      println()
    end
  else
    mpi_mode_help(cmd)
  end
end

push!(mpi_repl_mode.commands, CommandSpec(
  canonical_name = "help",
  api = mpi_mode_help,
  description = "Display help. Optionally specify a command name to display help for.",
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :cmd,
    ),
  )
))
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