export ContinuousElectricalChannel

"Electrical channel with a stepwise definition of values."
Base.@kwdef struct ContinuousElectricalChannel <: AcyclicElectricalTxChannel # TODO: Why is this named continuous?
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Divider of sampling frequency."
  dividerSteps::Integer
  "Divider of the component."
  divider::Integer
  "Amplitude (peak) of the component for each period of the field."
  amplitude::Union{typeof(1.0u"T"), typeof(1.0u"A"), typeof(1.0u"A")} # Is it really the right choice to have the periods here? Or should it be moved to the MagneticField?
  "Phase of the component for each period of the field."
  phase::typeof(1.0u"rad")
  "Offset of the channel. If defined in Tesla, the calibration configured in the scanner will be used."
  offset::Union{typeof(1.0u"T"), typeof(1.0u"A")} = 0.0u"T"
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

channeltype(::Type{<:ContinuousElectricalChannel}) = StepwiseTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{ContinuousElectricalChannel}, channelDict::Dict{String, Any})
  offset = uparse.(channelDict["offset"])
  if eltype(offset) <: Unitful.Current
    offset = offset .|> u"A"
  elseif eltype(offset) <: Unitful.Voltage
    offset = offset .|> u"V"
  elseif eltype(offset) <: Unitful.BField
    offset = offset .|> u"T"
  else
    error("The value for an offset has to be either given as a current or in tesla. You supplied the type `$(eltype(offset))`.")
  end

  dividerSteps = channelDict["dividerSteps"]
  divider = channelDict["divider"]

  if mod(divider, dividerSteps) != 0
    error("The divider $(divider) needs to be a multiple of the dividerSteps $(dividerSteps)")
  end

  amplitude = uparse.(channelDict["amplitude"])
  if eltype(amplitude) <: Unitful.Current
    amplitude = amplitude .|> u"A"
  elseif eltype(amplitude) <: Unitful.Voltage
    amplitude = amplitude .|> u"V"
  elseif eltype(amplitude) <: Unitful.BField
    amplitude = amplitude .|> u"T"
  else
    error("The value for an amplitude has to be either given as a current or in tesla. You supplied the type `$(eltype(amplitude))`.")
  end

  if haskey(channelDict, "phase")
    phase = uparse.(channelDict["phase"])
  else
    phase = 0.0u"rad"  # Default phase
  end

  if haskey(channelDict, "waveform")
    waveform = toWaveform(channelDict["waveform"])
  else
    waveform = WAVEFORM_SINE # Default to sine
  end

  @assert length(amplitude) == length(phase) "The length of amplitude and phase must match."
  return ContinuousElectricalChannel(;id=channelID, divider, offset, waveform, amplitude, phase, dividerSteps)
end

function values(channel::ContinuousElectricalChannel)
  numPatches = div(channel.divider, channel.dividerSteps)
  return [channel.offset + channel.amplitude*
                   value(channel.waveform, p/numPatches+channel.phase/(2*pi))
                       for p=0:(numPatches-1)]
end

cycleDuration(channel::ContinuousElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = baseFrequency/channel.divider