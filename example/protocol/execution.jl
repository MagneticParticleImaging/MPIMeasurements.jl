using MPIMeasurements, MPIFiles, REPL, REPL.TerminalMenus

include("logging.jl")
include("handler.jl")
include("config.jl")

handler = ProtocolScriptHandler(protocol, scanner; interval = interval, storage = storage, logpath = logpath);


execute(handler)