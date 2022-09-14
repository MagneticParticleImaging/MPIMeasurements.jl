function list_device_ids()
  if check_no_scanner()
    return getDeviceIDs(mpi_repl_mode.activeProtocolHandler.scanner)
  end
end

function device_mode_activate(;deviceID_::Union{String, Nothing} = nothing)
  if check_no_scanner()
    if isnothing(deviceID_)
      options = list_device_ids()
      menu = REPL.TerminalMenus.RadioMenu(options, pagesize=4)
      choice = REPL.TerminalMenus.request("Choose device:", menu)

      if choice != -1
        deviceID_ = options[choice]
      else
        println("Device selection canceled.")
        return
      end
    else
      if !(deviceID_ in list_device_ids())
        println("The selected device ID `$deviceID_` is not in the list of available device IDs. ")
        println("If you think this is a mistake, please check the scanner configuration.")
        return
      end
    end

    device_repl_mode.activeDeviceID = deviceID_
  else
    println("A device has already been activated. Please deactivate first.")
  end

  return
end

push!(device_repl_mode.commands, CommandSpec(
  canonical_name = "activate",
  short_name = "ac",
  api = device_mode_activate,
  option_specs = Dict{String, OptionSpec}(
    "default" => OptionSpec(
      name = "default",
      api = :deviceID_,
    ),
  ),
  completions = (input, final, offset, index) -> begin
    return [deviceID_ for deviceID_ in list_device_ids() if startswith(deviceID_, input)]
  end,
  description = "Activate a specific device or select from a list"
))

function device_mode_deactivate()
  device_repl_mode.activeDeviceID = nothing
end

push!(device_repl_mode.commands, CommandSpec(
  canonical_name = "deactivate",
  short_name = "deac",
  api = device_mode_deactivate,
  description = "Dectivate current device."
))

function device_mode_mpi()
  enter_mode!("MPI mode")

  return
end

push!(device_repl_mode.commands, CommandSpec(
  canonical_name = "mpi",
  api = device_mode_mpi,
  description = "Enter mode to interact with devices."
))

# Auxiliary commands

push!(device_repl_mode.commands, CommandSpec(
  canonical_name = "debug",
  api = mpi_mode_debug,
  description = "Set to debug mode."
))

push!(device_repl_mode.commands, CommandSpec(
  canonical_name = "exit",
  synonyms = ["exit()"],
  api = mpi_mode_exit,
  description = "Exit Julia."
))

include("Devices/Devices.jl")