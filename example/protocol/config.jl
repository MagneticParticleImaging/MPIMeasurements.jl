using Dates
# Scanner
reloadScanner = false                             # if the scanner should be reloaded for each execution
scannerName = "HomeScanner"                       # Which scanner to load


scannerDefined = @isdefined scanner
scanner = scannerDefined ? scanner : nothing
if reloadScanner || !scannerDefined 
  @info "Loading scanner"
  scanner = MPIScanner(scannerName, robust = true)
  @info "Finished loading scanner"
end

# Protocol
@info "Loading protocol"
protocol = Protocol("MPIMeasurement", scanner)
@info "Finished loading protocol"

# (Optional) Configure protocol parameters
params = protocol.params
params.fgFrames = 10

# Logging
logpath = joinpath(homedir(), ".mpi/Logs")        # Location of log files
loglevel = Logging.Info                           # Log Level of Term display
loglines = 30                                     # How many log lines to display

# Data Storage
# Where and how to store protocol data. Chose one option for the storage variable
# Option 1: No storage necessary
storage = NoStorageRequestHandler()

# Option 2: Store data in a file (T-Design Data)
storage = FileStorageRequestHandler("path")

# Option 3: Store an MDF. Here we require a datasetstorage and the skeleton of an MDF
mdf = defaultMDFv2InMemory()
# Study Options
studyName(mdf, "OurStudy")
studyTime(mdf, now())
studyDescription(mdf, "")
# Experiement
experimentDescription(mdf, "")
experimentName(mdf, "")
scannerOperator(mdf, "")
# Tracer
tracerName(mdf, [""])
tracerBatch(mdf, [""])
tracerVendor(mdf, [""])
tracerVolume(mdf, [1e-3*0.0])
# Concentration depends on the chosen unit
# mmol/L
conc = 1e-3*0.0
# mg/mL (1 mg/mL = 17.85 mmol/L)
conc = 17.85 * 1e-3*0.0
tracerConcentration(mdf, [conc])
tracerSolute(mdf, [""])
# DatasetStore
datastore = MDFDatasetStore(joinpath(homedir(), ".mpi", "data"))

storage = DatasetStoreStorageRequestHandler(datastore, mdf)

# How often to check the protocol for new events
interval = 0.01