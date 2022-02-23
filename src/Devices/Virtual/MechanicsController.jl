export MechanicsControllerParams, MechanicsController

Base.@kwdef mutable struct MechanicsControllerParams <: DeviceParams
  
end
MechanicsControllerParams(dict::Dict) = params_from_dict(MechanicsControllerParams, dict)

Base.@kwdef mutable struct MechanicsController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::MechanicsControllerParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}



end

function init(tx::MechanicsController)
  @info "Initializing MechanicsController with ID `$(tx.deviceID)`."
  tx.present = true
end

neededDependencies(::MechanicsController) = []
optionalDependencies(::MechanicsController) = [AbstractDAQ, Motor, Robot]

function setup(mechCont::MechanicsController, seq::Sequence)
  channels = mechanicalTxChannels(seq)

  for channel in channels
    device_ = dependency(mechCont, id(channel))

    if doesRotationMovement(channel) && !(device_ isa Motor)
      throw(ScannerConfigurationError("The rotation channel with id `$(id(channel))` has a corresponding device which is not of type `Motor`."))
    end
    if doesRotationMovement(channel)
      @debug "Setting up motor"
      # Setup motor
    end

    if doesTranslationMovement(channel) && !(device_ isa Robot)
      throw(ScannerConfigurationError("The translation channel with id `$(id(channel))` has a corresponding device which is not of type `Robot`."))
    end
    if doesTranslationMovement(channel)
      @debug "Setting up motor"
      # Setup robot
    end
  end


  # StepwiseMechanicalRotationChannel
  # StepwiseMechanicalTranslationChannel
  # ContinuousMechanicalRotationChannel
  # ContinuousMechanicalTranslationChannel

  # Setup all continuous channels because they can just run


end

