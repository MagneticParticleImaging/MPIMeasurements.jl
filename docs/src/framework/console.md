# Console Modes

`MPIMeasurements.jl` registers two additional REPL modes when the package is loaded
(`MPIMeasurements.__init__()`). They provide a command-line interface to a `Scanner` and to
individual `Device`s, without having to write Julia code.

| Mode | Start key | Prompt |
| --- | --- | --- |
| MPI mode | `Alt+1` (`start_key = "\\M-1"`) | `MPI> `, or `MPI (<scanner>)> ` when a scanner is active |
| Device mode | `Alt+2` (`start_key = "\\M-2"`) | `DEV> `, or `DEV (<deviceID>)> ` when a device is active |

Press the start key in the Julia REPL to switch into the respective mode. Both modes support
tab completion for command names and their arguments; typing `?` before a partial command
(e.g. `?act` followed by `Tab`) completes against the available commands.

Use `help` to list all commands of the current mode, or `help <command>` for a single command.

## MPI mode

MPI mode operates on a `Scanner`. A scanner must be activated before most commands work.

| Command | Short | Description |
| --- | --- | --- |
| `activate [scanner]` | `ac` | Activate a scanner. Without an argument the `scanner` entry of `~/.mpi/Settings.toml` is used, otherwise a selection menu is shown. |
| `deactivate` | `deac` | Deactivate the current scanner. |
| `attach <variable>` | `att` | Attach to an existing `MPIScanner` held in a Julia variable. |
| `detach` | | Detach the current scanner and return it. |
| `get <what>` | | Retrieve a `device`, `protocol`, `params`, `sequence` or `scanner`; the result is stored in `ans`. |
| `init [protocol]` | | Initialize a protocol. Defaults to the scanner's `defaultProtocol`. |
| `start` | | Start the initialized protocol. |
| `end` | | End the running protocol (synonym: `stop`). |
| `study` | | Show and set study parameters. |
| `experiment` | | Show and set experiment parameters. |
| `tracer` | | Show and set tracer parameters. |
| `operator` | | Show and set the operator. |
| `device` | | Switch to Device mode. |
| `debug` | | Enable/disable `JULIA_DEBUG=all`. |
| `exit` | | Exit Julia. |
| `help [command]` | | Display help. |

A typical session:

```julia-repl
MPI> activate 3DAWMPS
Activating scanner `3DAWMPS`.
MPI (3DAWMPS)> init SimpleMPSMeasurement
MPI (3DAWMPS)> start
MPI (3DAWMPS)> end
MPI (3DAWMPS)> deactivate
```

!!! warning
    `activate` constructs an `MPIScanner`, which initializes all configured devices and opens
    serial and network connections. `start` energizes amplifiers and coils. Only do this when
    the hardware is safe to operate.

## Device mode

Device mode operates on a single `Device` of the currently activated scanner.

| Command | Short | Description |
| --- | --- | --- |
| `activate [deviceID]` | `ac` | Activate a device, either by ID or from a selection list. |
| `deactivate` | `deac` | Deactivate the current device. |
| `mpi` | | Switch to MPI mode. |
| `debug` | | Enable/disable `JULIA_DEBUG=all`. |
| `exit` | | Exit Julia. |

In addition, each `Device` type can register its own commands via the `@devicecommand` macro.
These are only available while a device of that type is active. For example:

- `RedPitayaDAQ`: `update`, `update <tag>`, `calibrate`
- `Robot`: `enable`, `disable`, `reset`, `reference`, `referenced`, `move <type> <position>`, `position`

```julia-repl
MPI> activate 3DAWMPS
MPI (3DAWMPS)> device rp_cluster
DEV (rp_cluster)> update
DEV (rp_cluster)> deactivate
DEV> mpi
MPI (3DAWMPS)>
```
