export SequenceControllerParams, SequenceController, getSequenceControllers,
       getSequenceController, setupSequence, startSequence, cancel, trigger

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  "Number of frames after which the data should be saved to a mmapped temp file."
  numFrameSave::Integer = 1
end

SequenceControllerParams(dict::Dict) = params_from_dict(SequenceControllerParams, dict)

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SequenceControllerParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  sequence::Union{Sequence, Nothing} = nothing

  startTime::Union{DateTime, Nothing} = nothing
  task::Union{Task, Nothing} = nothing
  trigger::Channel{Int64} = Channel{Int64}(8)
  triggerCount::Threads.Atomic{Int64} = Threads.Atomic{Int64}(0)
  cancelled::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
  done::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
  buffer::Vector{Array{Float32, 4}} = []
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

checkDependencies(seqCont::SequenceController) = true # TODO: Add daq

setupControlLoop() = @warn "control loop not yet implemented"

function setupSequence(seqCont::SequenceController, sequence::Sequence)
  seqCont.sequence = sequence
  daq = dependency(seqCont, AbstractDAQ) # This doesn't work for multiple DAQs yet, since this case is not really a priority

  @debug "controller called"
  setupControlLoop() #TODO: Check which fields have to be controlled
  electricalChannels = electricalTxChannels(seqCont.sequence)
  setupTx(daq, electricalChannels, txBaseFrequency(seqCont.sequence))

  # TODO: Setup mechanical channels

  setupRx(daq, rxChannels(sequence), acqNumPeriodsPerFrame(sequence), rxNumSamplingPoints(sequence))
end

function startSequence(seqCont::SequenceController)
  if isnothing(seqCont.task) && !seqCont.cancelled[]
    #seqCont.running = true
    

    # Spawn acquisition thread
    if Threads.nthreads() == 1
      @warn "You are currently just using one thread. This could be troublesome in some cases "*
            "(e.g. with an acquisition running while also having a temperature controller running)"
    end

    @info "Starting acquisition thread."
    seqCont.task = @tspawnat 2 acquisitionThread(seqCont)
    sleep(0.1)

    @debug "Trigger first acquisition"
    #trigger(seqCont) # Trigger the first acquisition
  else
    @info "The sequence is already running"
  end
end

function cancel(seqCont::SequenceController)
  if isnothing(seqCont.task) ||!istaskstarted(seqCont.task)
    @info "The sequence is not running and can therefore not be cancelled."
  else
    seqCont.cancelled[] = true
    finish(seqCont) # Has to be called in order to stop the thread from waiting for triggers
  end
end

function trigger(seqCont::SequenceController)
  Threads.atomic_add!(seqCont.triggerCount, 1)
  put!(seqCont.trigger, seqCont.triggerCount[])
end

function finish(seqCont::SequenceController)
  put!(seqCont.trigger, -1) # Signals the acquisition thread to get out of the loop
end

function wait(seqCont::SequenceController)
  while !seqCont.done[]
    sleep(0.1)
  end
end

function acquisitionThread(seqCont::SequenceController)
  # currFr = enableSlowDAC(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
  #                          daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

  seqCont.startTime = now()
  @info "The acquisition thread just started (start time is $(seqCont.startTime))."

  seqScratchDirectory = @get_scratch!(seqCont.sequence.name)
  @info "The scratch directory for intermediate data is `$seqScratchDirectory`."

  # rxNumSamplingPoints_ = rxNumSamplingPoints(seqCont.sequence)
  # numPeriods = acqNumPeriodsPerFrame(seqCont.sequence)

  # # Use surveillance unit if available
  # if hasDependency(seqCont, SurveillanceUnit)
  #   su = dependency(seqCont, SurveillanceUnit)
  #   enableACPower(su)
  # else
  #   @warn "The sequence controller does not have access to a surveillance unit. "*
  #         "Please check closely if this should be the case."
  # end

  # daq = dependency(seqCont, AbstractDAQ)
  # @info "Starting transmit part of the sequence"
  # startTx(daq)

  # TODO: Control
  @warn "The control loop should be started here"

  while !seqCont.cancelled[]
    @info "Waiting for acquisition trigger."
    currTriggerCount = take!(seqCont.trigger)

    if currTriggerCount == -1
      @info "The acquisition thread received the signal to finish acquisition and will now return."
      break
    end

    @info "Received an acquisition trigger. The current count is $currTriggerCount."

    if seqCont.cancelled[]
      @debug "The acquisition thread was cancelled while waiting for a trigger."
      break
    end

    # numFrames = acqNumFrames(seqCont.sequence)
    # if length(numFrames) > 1
    #   if length(numFrames) <= currTriggerCount
    #     numFrames = numFrames[currTriggerCount]
    #   else
    #     @error "The specified amount of possible triggers for the number of frames is "*
    #            "$(length(numFrames)), but an additional trigger has been applied."
    #     break
    #   end
    # end

    # triggerFilename = joinpath(seqScratchDirectory, "$(seqCont.startTime)_trigger_$(currTriggerCount).bin")
    # shape = (rxNumSamplingPoints, numRxChannels(daq), numPeriods, numFrames)
    # triggerBuffer = Mmap.mmap(triggerFilename, Matrix{Int}, shape)


    # fr = 1
    # while fr <= daq.params.acqNumFrames
    #   to = min(fr+chunk-1,daq.params.acqNumFrames) 

    #   #if tempSensor != nothing
    #   #  for c = 1:numChannels(tempSensor)
    #   #      measState.temperatures[c,fr] = getTemperature(tempSensor, c)
    #   #  end
    #   #end
    #   @info "Measuring frame $fr to $to"
    #   @time uMeas, uRef = readData(daq, daq.params.acqNumFrameAverages*(length(fr:to)),
    #                               currFr + (fr-1)*daq.params.acqNumFrameAverages)
    #   @info "It should take $(daq.params.acqNumFrameAverages*(length(fr:to))*framePeriod)"
    #   s = size(uMeas)
    #   @info s
    #   if daq.params.acqNumFrameAverages == 1
    #     measState.buffer[:,:,:,fr:to] = uMeas
    #   else
    #     tmp = reshape(uMeas, s[1], s[2], s[3], daq.params.acqNumFrameAverages, :)
    #     measState.buffer[:,:,:,fr:to] = dropdims(mean(uMeas, dims=4),dims=4)
    #   end
    #   measState.currFrame = fr
    #   measState.consumed = false
    #   #sleep(0.01)
    #   #yield()
    #   fr += chunk

    #   # Write the current chunk to our temp file
    #   Mmap.sync!()

    #   if measState.cancelled
    #     break
    #   end
    # end

    
  end
  
  #sleep(daq.params.ffRampUpTime)
  # stopTx(daq)
  # if hasDependency(seqCont, SurveillanceUnit)
  #   disableACPower(su, scanner)
  # end
  # disconnect(daq)

  # if length(measState.temperatures) > 0
  #   params["calibTemperatures"] = measState.temperatures
  # end

  seqCont.done[] = true
end

function fillMDF(seqCont::SequenceController, mdf::MDFv2InMemory)
  # /acquisition/ subgroup
  acqGradient(mdf, acqGradient(seqCont.sequence))
  acqNumAverages(mdf, acqNumAverages(seqCont.sequence))
  acqNumFrames(mdf, acqNumFrames(seqCont.sequence)) # TODO: Calculate from data (triggered acquisition)
  acqNumPeriodsPerFrame(mdf, acqNumPeriodsPerFrame(seqCont.sequence))
  acqOffsetField(mdf, acqOffsetField(seqCont.sequence))
  acqStartTime(mdf, seqCont.startTime)

  # /acquisition/drivefield/ subgroup
  dfBaseFrequency(mdf, ustrip(u"Hz", dfBaseFrequency(seqCont.sequence)))
  dfCycle(mdf, ustrip(u"s", dfCycle(seqCont.sequence)))
  dfDivider(mdf, dfDivider(seqCont.sequence))
  dfNumChannels(mdf, dfNumChannels(seqCont.sequence))
  dfPhase(mdf, ustrip.(u"rad", dfPhase(seqCont.sequence)))
  dfStrength(mdf, ustrip.(u"T", dfStrength(seqCont.sequence)))
  dfWaveform(mdf, fromWaveform.(dfWaveform(seqCont.sequence)))

  # /acquisition/receiver/ subgroup
  rxBandwidth(mdf, ustrip(u"Hz", rxBandwidth(seqCont.sequence)))
  #dataConversionFactor TODO: Should we include it or convert the samples directly
  #inductionFactor TODO: should be added from datastore!?
  rxNumChannels(mdf, rxNumChannels(seqCont.sequence))
  rxNumSamplingPoints(mdf, rxNumSamplingPoints(seqCont.sequence))
  #transferFunction TODO: should be added from datastore!?
  rxUnit(mdf, "V")
end