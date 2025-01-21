using MPIMeasurements, MPIFiles, Term, Term.LiveWidgets

include("widget.jl")
include("logging.jl")
include("handler.jl")
include("config.jl")

handler = ProtocolScriptHandler(protocol, scanner; interval = interval, storage = storage, logpath = logpath);


play(handler)