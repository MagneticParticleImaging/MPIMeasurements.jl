export MechanicsControllerParams, MechanicsController

Base.@kwdef mutable struct MechanicsControllerParams <: DeviceParams
  
end
MechanicsControllerParams(dict::Dict) = params_from_dict(MechanicsControllerParams, dict)

Base.@kwdef mutable struct MechanicsController <: VirtualDevice
  @add_device_fields MechanicsControllerParams

  sequence::Union{Sequence, Nothing} = nothing
  channelSteps::Union{Dict{String, Int64}, Nothing} = nothing
end

function init(tx::MechanicsController)
  @info "Initializing MechanicsController with ID `$(tx.deviceID)`."
  tx.present = true
end

neededDependencies(::MechanicsController) = []
optionalDependencies(::MechanicsController) = [AbstractDAQ, Motor, Robot]

Base.close(mechCont::MechanicsController) = nothing

function setup(mechCont::MechanicsController, seq::Sequence)
  mechCont.sequence = seq
  controlledChannels = mechanicalTxChannels(seq)

  for channel in controlledChannels
    device_ = dependency(mechCont, id(channel))

    if doesRotationMovement(channel) && !(device_ isa Motor)
      throw(ScannerConfigurationError("The rotation channel with id `$(id(channel))` has a corresponding device which is not of type `Motor`."))
    end
    if doesRotationMovement(channel)
      @debug "Setting up rotation motor"
      # Setup motor
    end

    if doesTranslationMovement(channel) && !(device_ isa Robot)
      throw(ScannerConfigurationError("The translation channel with id `$(id(channel))` has a corresponding device which is not of type `Robot`."))
    end
    if doesTranslationMovement(channel)
      @debug "Setting up translation robot"
      # Setup robot
    end
  end


  # StepwiseMechanicalRotationChannel
  # StepwiseMechanicalTranslationChannel
  # ContinuousMechanicalRotationChannel
  # ContinuousMechanicalTranslationChannel

  # Setup all continuous channels because they can just run


end

function currentNumberOfSteps(mechCont::MechanicsController)
  if isnothing(mechCont.sequence)
    return 0
  end

  controlledChannels = stepwiseMechanicalTxChannels(mechCont.sequence)
  sort!(controlledChannels)
  reverse!(controlledChannels)

  currentNumberOfSteps_ = 1
  for (idx, channel) in enumerate(controlledChannels[1:end-1])

    fullChannelNumberOfSteps = 1
    for fullChannel in controlledChannels[idx+1:end-1]
      fullChannelNumberOfSteps *= stepsPerCycle(fullChannel)
    end

    currentNumberOfSteps_ += fullChannelNumberOfSteps*mechCont.channelSteps[id(channel)]
  end

  currentNumberOfSteps_ += mechCont.channelSteps[id(controlledChannels[end])]

  return currentNumberOfSteps_
end

function totalNumberOfSteps(mechCont::MechanicsController)
  if isnothing(mechCont.sequence)
    return 0
  end

  controlledChannels = stepwiseMechanicalTxChannels(mechCont.sequence)
  sort!(controlledChannels)
  reverse!(controlledChannels)

  totalNumberOfSteps_ = 1
  for channel in controlledChannels
    totalNumberOfSteps_ *= stepsPerCycle(channel)
  end

  return totalNumberOfSteps_
end

function doStep(mechCont::MechanicsController)
  if isnothing(mechCont.sequence)
    error("There is no sequence to control and thus no channels for doing a step. Has `setup` been called?")
  end

  # Check if we have any channels to perform steps on
  if !hasStepwiseMechanicalChannels(mechCont.sequence)
    return false
  end

  controlledChannels = stepwiseMechanicalTxChannels(mechCont.sequence)

  # Setup counting of steps
  if isnothing(mechCont.channelSteps)
    mechCont.channelSteps = Dict{String, Int64}()
    for channel in controlledChannels
      mechCont.channelSteps[id(channel)] = 0
    end
  end

  # Determine next channel to perform step
  sort!(controlledChannels)
  selectedChannel = nothing
  for (idx, channel) in enumerate(controlledChannels)
    if mechCont.channelSteps[id(channel)] < stepsPerCycle(channel)
      selectedChannel = channel
      mechCont.channelSteps[id(channel)] += 1
      continue
    elseif idx == length(controlledChannels) # The last channel has performed all steps
      return false
    end
  end

  stepDevice = dependency(mechCont, id(selectedChannel))

  # Pre-step pause
  sleep(ustrip(u"s", preStepPause(selectedChannel)))

  # Do step
  if stepDevice isa Motor # TODO: Should only be stepper motors
    driveSteps(stepDevice, 1)
  elseif stepDevice isa Robot
    # TODO: Add robot code for postions
  else
    ScannerConfigurationError("The device with ID `$(deviceID(stepDevice))` and type `$(typeof(stepDevice))` is not a valid device for perfroming a step.")
  end

  # Post-step pause
  sleep(ustrip(u"s", postStepPause(selectedChannel)))

  return true
end

