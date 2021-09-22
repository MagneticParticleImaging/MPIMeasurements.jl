export RobotBasedSystemMatrixProtocol, RobotBasedSystemMatrixProtocolParams

Base.@kwdef struct RobotBasedSystemMatrixProtocolParams <: RobotBasedProtocolParams
  sequenceName::AbstractString
end
RobotBasedSystemMatrixProtocolParams(dict::Dict) = params_from_dict(RobotBasedSystemMatrixProtocolParams, dict)

Base.@kwdef mutable struct RobotBasedSystemMatrixProtocol <: RobotBasedProtocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::RobotBasedSystemMatrixProtocolParams
  
  sequence::Union{Sequence, Missing} = missing
  mdf::Union{MDFv2InMemory, Missing} = missing
  filename::AbstractString = ""
end

sequenceName(protocol::RobotBasedSystemMatrixProtocol) = protocol.params.sequenceName
sequence(protocol::RobotBasedSystemMatrixProtocol) = protocol.sequence
mdf(protocol::RobotBasedSystemMatrixProtocol) = protocol.mdf

#TODO: This has currently no link to an MDF store. How should we integrate it?
function prepareMDF(protocol::RobotBasedSystemMatrixProtocol, filename::AbstractString, study::MDFv2Study, experiment::MDFv2Experiment, operator::AbstractString="anonymous")
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

function init(protocol::RobotBasedSystemMatrixProtocol)
  scanner_ = scanner(protocol)
  configDir_ = configDir(scanner_)
  sequenceName_ = sequenceName(protocol)
  filename = joinpath(configDir_, "Sequences", "$sequenceName_.toml")
  protocol.sequence = Sequence(filename)
end

function execute(protocol::RobotBasedSystemMatrixProtocol)
 
  @info "Protocol finished."
end

function cleanup(protocol::RobotBasedSystemMatrixProtocol)
  
end