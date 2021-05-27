export SequenceControllerParams, SequenceController, getSequenceControllers,
       getSequenceController, setupSequence

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  
end

SequenceControllerParams(dict::Dict) = params_from_dict(SequenceControllerParams, dict)

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SequenceControllerParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  running::Bool = false
end

function getSequenceControllers(scanner::MPIScanner)
  sequenceControllers = getDevices(scanner, SequenceController)
  if length(sequenceControllers) > 1
    throw(ScannerConfigurationError("The scanner has more than one sequence controller device. This should never happen."))
  else
    return sequenceControllers
  end
end
function getSequenceController(scanner::MPIScanner)
  sequenceControllers =  getSequenceControllers(scanner)
  if length(sequenceControllers) == 0
    throw(ScannerConfigurationError("The scanner has no sequence controller device but one was requested. "*
                                    "Check your scanner configuration as well as your protocol."))
  else
    return sequenceControllers[1]
  end
end

function init(seqCont::SequenceController)
  @info "Initializing sequence controller with ID `$(seqCont.deviceID)`."
end

checkDependencies(seqCont::SequenceController) = true

setupControlLoop() = @warn "control loop not yet implemented"

function setupSequence(seqCont::SequenceController, sequence::Sequence)
  daq = dependency(seqCont, AbstractDAQ) # This doesn't work for multiple DAQs yet, since this case is not really a priority

  @debug "controller called"
  setupControlLoop() #TODO: Check which fields have to be controlled
  electricalChannels = electricalTxChannels(sequence)
  setupTx(daq, electricalChannels, sequence.baseFrequency)

  # TODO: Setup mechanical channels

  # TODO: Dirty hack for now; have to choose where to put it
  numSamplingPoints = round(Int64, 125e6/25e3)

  setupRx(daq, sequence.rxChannels, sequence.numPeriodsPerFrame, numSamplingPoints)
end

function startSequence(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)
  startTx(daq)
end

function stopSequence(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)
  stopTx(daq)
end

function trigger(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)
  trigger(daq)
end