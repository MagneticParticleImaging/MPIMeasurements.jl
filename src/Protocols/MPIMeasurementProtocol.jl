export MPIMeasurementProtocol, MPIMeasurementProtocolParams, sequenceName, sequence, mdf, prepareMDF

Base.@kwdef struct MPIMeasurementProtocolParams <: ProtocolParams
  sequenceName::AbstractString
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MPIMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MPIMeasurementProtocolParams
  
  sequence::Union{Sequence, Missing} = missing
  mdf::Union{MDFv2InMemory, Missing} = missing
  filename::AbstractString = ""
end

sequenceName(protocol::MPIMeasurementProtocol) = protocol.params.sequenceName
sequence(protocol::MPIMeasurementProtocol) = protocol.sequence
mdf(protocol::MPIMeasurementProtocol) = protocol.mdf

#TODO: This has currently no link to an MDF store. How should we integrate it?
function prepareMDF(protocol::MPIMeasurementProtocol, filename::AbstractString, study::MDFv2Study, experiment::MDFv2Experiment, operator::AbstractString="anonymous")
  protocol.mdf = MDFv2InMemory()
  protocol.mdf.root = defaultMDFv2Root()
  protocol.mdf.study = study
  protocol.mdf.experiment = experiment
  protocol.mdf.scanner = MDFv2Scanner(
    boreSize = ustrip(u"m", scannerBoreSize(protocol.scanner)),
    facility = scannerFacility(protocol.scanner),
    manufacturer = scannerManufacturer(protocol.scanner),
    name = scannerName(protocol.scanner),
    operator = operator,
    topology = scannerTopology(protocol.scanner)
  )

  protocol.filename = filename
end

function init(protocol::MPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  configDir_ = configDir(scanner_)
  sequenceName_ = sequenceName(protocol)
  filename = joinpath(configDir_, "Sequences", "$sequenceName_.toml")
  protocol.sequence = Sequence(filename)
end

function execute(protocol::MPIMeasurementProtocol)
  scanner_ = scanner(protocol)
  controller = getMeasurementController(scanner_)

  uMeas = MPIMeasurements.measurement(controller, protocol.sequence)

  if !ismissing(protocol.mdf)
    @info "Sequence finished. Now saving to MDF."
    fillMDF(seqCont, protocol.mdf)
    saveasMDF(protocol.filename, protocol.mdf)
  else
    @warn "No MDF defined and thus, no data is saved. If this is a mistake "*
          "please run `prepareMDF` prior to calling `runProtocol`."
  end
  @info "Protocol finished."
end

function cleanup(protocol::MPIMeasurementProtocol)
  
end