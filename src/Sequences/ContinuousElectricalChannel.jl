export ContinuousElectricalChannel

"Electrical channel with a stepwise definition of values."
Base.@kwdef mutable struct ContinuousElectricalChannel <: AcyclicElectricalTxChannel # TODO: Why is this named continuous?
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Divider of sampling frequency."
  dividerSteps::Integer
  "Divider of the component."
  divider::Integer
  "Amplitude (peak) of the component for each period of the field."
  amplitude::Union{typeof(1.0u"A"), typeof(1.0u"V"), typeof(1.0u"T")} # Is it really the right choice to have the periods here? Or should it be moved to the MagneticField?
  "Phase of the component for each period of the field."
  phase::typeof(1.0u"rad")
  "Offset of the channel. If defined in Tesla, the calibration configured in the scanner will be used."
  offset::Union{typeof(1.0u"T"), typeof(1.0u"V"), typeof(1.0u"A")} = 0.0u"T"
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

unitIsTesla(chan::ContinuousElectricalChannel) = (dimension(chan.offset) == dimension(u"T")) && (dimension(chan.amplitude)==dimension(u"T"))

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
    phaseDict = Dict("cosine"=>0.0u"rad", "cos"=>0.0u"rad","sine"=>pi/2u"rad", "sin"=>pi/2u"rad","-cosine"=>pi*u"rad", "-cos"=>pi*u"rad","-sine"=>-pi/2u"rad", "-sin"=>-pi/2u"rad")
    
    try
      phase = uparse(channelDict["phase"])
    catch
      if haskey(phaseDict, channelDict["phase"])
        phase = phaseDict[channelDict["phase"]]
      else
        error("The value $(channelDict["phase"]) for the phase could not be parsed. Use either a unitful value, or one of the predefined keywords ($(keys(phaseDict)))")
      end
    end     
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
  if channel.waveform == WAVEFORM_SAWTOOTH_RISING
    temp = channel.offset .+ channel.amplitude .*collect(range(-1, stop=1, length=numPatches)) 
    return circshift(temp, ceil(Int,channel.phase/(2*pi)*length(temp)) ) 
  elseif channel.waveform == WAVEFORM_SAWTOOTH_FALLING
    temp = channel.offset .+ channel.amplitude .*collect(range(1, stop=-1, length=numPatches)) 
    return circshift(temp, ceil(Int,channel.phase/(2*pi)*length(temp)) )
  elseif channel.waveform == WAVEFORM_TRIANGLE
    temp = channel.offset .+ channel.amplitude .* [4*abs((x/numPatches - floor(x/numPatches + 1/2))) - 1  for x in 1:numPatches]
    return circshift(temp, ceil(Int, channel.phase/(2*pi)*length(temp)))
  else
    return [channel.offset + channel.amplitude*
                   value(channel.waveform, p/numPatches+channel.phase/(2*pi))
                       for p=0:(numPatches-1)]
  end 
end

cycleDuration(channel::ContinuousElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = baseFrequency/channel.divider

function enableValues(channel::ContinuousElectricalChannel)
  numPatches = div(channel.divider, channel.dividerSteps)
  return [true for p=0:(numPatches-1)]
end