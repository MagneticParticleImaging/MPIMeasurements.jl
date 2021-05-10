export SequenceControllerParams, SequenceController, getSequenceControllers,
       getSequenceController, setupSequence

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  
end

SequenceControllerParams(dict::Dict) = from_dict(SequenceControllerParams, dict)

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  deviceID::String
  params::SequenceControllerParams
  running::Bool = false
end

getSequenceControllers(scanner::MPIScanner) = getDevices(scanner, SequenceController)
function getSequenceController(scanner::MPIScanner)
  sequenceControllers = getSequenceControllers(scanner)
  if length(sequenceControllers) > 1
    error("The scanner has more than one sequence controller device. This should never happen.")
  else
    return sequenceControllers[1]
  end
end

setupControlLoop() = @warn "control loop not yet implemented"

function setupSequence(scanner::MPIScanner, sequence::Sequence)
  @info "controller called"
  setupControlLoop() #TODO: Check which fields have to be controlled
  electricalChannels = electricalTxChannels(sequence)
  sequenceController = getSequenceController(scanner)
  daq = getDAQ(scanner) # This doesn't work for multiple DAQs yet, since this case is not really a priority
  setupTx(daq, electricalChannels, sequence.baseFrequency)

  # TODO: Setup mechanical channels

  # TODO: Dirty hack for now; have to choose where to put it
  numSamplingPoints = round(Int64, 125e6/25e3)

  setupRx(daq, sequence.rxChannels, sequence.numPeriodsPerFrame, numSamplingPoints)
end

function startSequence(scanner::MPIScanner)
  daq = getDAQ(scanner)
  startTx(daq)
end

function stopSequence(scanner::MPIScanner)
  daq = getDAQ(scanner)
  stopTx(daq)
end