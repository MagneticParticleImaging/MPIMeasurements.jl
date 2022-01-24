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
  channels = mechanicalTxChannels



  # Setup all continuous channels because they can just run

  # Prepare 

  # Prepare and check channel under control
  daq = dependency(mechCont, AbstractDAQ)
  seqControlledChannel = getControlledChannel(seq)
  missingControlDef = []
  mechCont.controlledChannels = []

  for seqChannel in seqControlledChannel
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    if isnothing(daqChannel) || isnothing(daqChannel.feedback) || !in(daqChannel.feedback.channelID, daq.refChanIDs)
      push!(missingControlDef, name)
    else
      push!(mechCont.controlledChannels, ControlledChannel(seqChannel, daqChannel))
    end
  end
  
  if length(missingControlDef) > 0
    message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and") * ", but either the channel was not defined or had no defined feedback channel."
    throw(IllegalStateException(message))
  end

  # Check that channels only have one component
  if any(x -> length(x.components) > 1, seqControlledChannel)
    throw(IllegalStateException("Sequence has channel with more than one component. Such a channel cannot be controlled by this controller"))
  end

  if !isnothing(initTx) 
    s = size(initTx)
    # Not square or does not fit controlled channel matrix
    if !(length(s) == 0 || all(isequal(s[1]), s))
      throw(IllegalStateException("Given initTx for control tx has dimenions $s that is either not square or does not match the amount of controlled channel"))
    end
  end

  # Prepare values
  if isnothing(initTx)
    mechCont.currTx = convert(Matrix{ComplexF64}, diagm(ustrip.(u"V", [channel.daqChannel.limitPeak/10 for channel in mechCont.controlledChannels])))
  else 
    mechCont.currTx = initTx
  end
  sinLUT, cosLUt = createLUTs(seqControlledChannel, seq::Sequence)
  mechCont.sinLUT = sinLUT
  mechCont.cosLUT = cosLUt
  Ω = calcDesiredField(seqControlledChannel)

  # Start Tx
  setTxParams(daq, txFromMatrix(mechCont, mechCont.currTx)...)
  startTx(daq)

  controlPhaseDone = false
  i = 1
  while !controlPhaseDone && i <= mechCont.params.maxControlSteps
    @info "CONTROL STEP $i"
    period = currentPeriod(daq)
    uMeas, uRef = readDataPeriods(daq, 1, period + 1, acqNumAverages(seq))

    controlPhaseDone = doControlStep(mechCont, seq, uRef, Ω)

    sleep(mechCont.params.controlPause)
    i += 1
  end
  stopTx(daq)
  setTxParams(daq, txFromMatrix(mechCont, mechCont.currTx)...)
  return txFromMatrix(mechCont, mechCont.currTx)
end

