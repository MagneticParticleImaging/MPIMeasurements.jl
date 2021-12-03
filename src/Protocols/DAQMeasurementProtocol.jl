export DAQMeasurementProtocol, DAQMeasurementProtocolParams, sequenceName, sequence, mdf, prepareMDF

Base.@kwdef struct DAQMeasurementProtocolParams <: ProtocolParams
  sequenceName::AbstractString
end
DAQMeasurementProtocolParams(dict::Dict) = params_from_dict(DAQMeasurementProtocolParams, dict)

Base.@kwdef mutable struct DAQMeasurementProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::DAQMeasurementProtocolParams
  
  sequence::Union{Sequence, Missing} = missing
  mdf::Union{MDFv2InMemory, Missing} = missing
  filename::AbstractString = ""
end

sequenceName(protocol::DAQMeasurementProtocol) = protocol.params.sequenceName
sequence(protocol::DAQMeasurementProtocol) = protocol.sequence
mdf(protocol::DAQMeasurementProtocol) = protocol.mdf

#TODO: This has currently no link to an MDF store. How should we integrate it?
function prepareMDF(protocol::DAQMeasurementProtocol, filename::AbstractString, study::MDFv2Study, experiment::MDFv2Experiment, operator::AbstractString="anonymous")
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

function init(protocol::DAQMeasurementProtocol)
  scanner_ = scanner(protocol)
  configDir_ = configDir(scanner_)
  sequenceName_ = sequenceName(protocol)
  filename = joinpath(configDir_, "Sequences", "$sequenceName_.toml")
  protocol.sequence = Sequence(filename)
end

function execute(protocol::DAQMeasurementProtocol)
  scanner_ = scanner(protocol)
  seqCont = getSequenceController(scanner_)

  setupSequence(seqCont, sequence(protocol))
  startSequence(seqCont)

  # Give the acquisition thread some time, so we don't have mixed up messages when prompting for input
  waitTriggerReady(seqCont)

  numTriggers = length(acqNumFrames(seqCont.sequence))
  if numTriggers > 2
    @error "The DAQMeasurementProtocol is only designed to acquire with one trigger "*
           "(just foreground frames) or two triggers (background and foreground frames). "*
           "Please ckeck the associated sequence configuration."
  elseif numTriggers == 1
    @info "This configuration of the DAQMeasurementProtocol only reads foreground frames."
    decision = askConfirmation("Do you have everything prepared to start the measurement? "*
                               "If the answer is no, the protocol will be stopped.")
    if decision
      trigger(seqCont)
    else
      finish(seqCont)
      wait(seqCont)
      @info "Protocol stopped"
      return
    end
  elseif numTriggers == 2
    decision = askConfirmation("Do you have removed the sample in order to take the background measurement "*
                                "and do you want to start?\nIf the answer is no, the protocol will be stopped ")
    if decision
      trigger(seqCont, true)
    else
      finish(seqCont)
      wait(seqCont)
      @info "Protocol stopped"
      return
    end

    waitTriggerReady(seqCont)

    decision = askConfirmation("Do you have everything prepared to start the foreground measurement?\n"*
                                "If the answer is no, the protocol will be stopped.")
    if decision
      trigger(seqCont, false)
    else
      finish(seqCont)
      wait(seqCont)
      @info "Protocol stopped"
      return
    end
  end

  @info "All triggers applied. Now finishing sequence."
  finish(seqCont)
  wait(seqCont)
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

function cleanup(protocol::DAQMeasurementProtocol)
  
end