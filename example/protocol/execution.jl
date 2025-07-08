using MPIMeasurements, MPIFiles, GLMakie

include("handler.jl")
include("config.jl")

handler = ProtocolScriptHandler(protocol, scanner; interval = interval, storage = storage, logpath = logpath);

# Show the GUI
show_gui(handler)