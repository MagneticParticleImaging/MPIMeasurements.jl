# TODO: Can this type be removed in favor of ContinuousElectricalChannel?

export PeriodicElectricalComponent, SweepElectricalComponent, PeriodicElectricalChannel

"Component of an electrical channel with periodic base function."
Base.@kwdef struct PeriodicElectricalComponent <: ElectricalComponent
  id::AbstractString
  "Divider of the component."
  divider::Integer
  "Amplitude (peak) of the component for each period of the field."
  amplitude::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"V")}} # Is it really the right choice to have the periods here? Or should it be moved to the MagneticField?
  "Phase of the component for each period of the field."
  phase::Vector{typeof(1.0u"rad")}
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

"Sweepable component of an electrical channel with periodic base function.
Note: Does not allow for changes in phase since this would make the switch
between frequencies difficult."
Base.@kwdef struct SweepElectricalComponent <: ElectricalComponent
  "Divider of the component."
  divider::Vector{Integer}
  "Amplitude (peak) of the channel for each divider in the sweep. Must have the same dimension as `divider`."
  amplitude::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"V")}}
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

"""Electrical channel based on based on periodic base functions. Only the
PeriodicElectricalChannel counts for the cycle length calculation"""
Base.@kwdef struct PeriodicElectricalChannel <: ElectricalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Components added for this channel."
  components::Vector{ElectricalComponent}
  "Offset of the channel. If defined in Tesla, the calibration configured in the scanner will be used."
  offset::Union{typeof(1.0u"T"), typeof(1.0u"V")} = 0.0u"T"
end

channeltype(::Type{<:PeriodicElectricalChannel}) = ContinuousTxChannel()

function createFieldChannel(channelID::AbstractString, channelType::Type{PeriodicElectricalChannel}, channelDict::Dict{String, Any})
  splattingDict = Dict{Symbol, Any}()
  splattingDict[:id] = channelID

  if haskey(channelDict, "offset")
    tmp = uparse.(channelDict["offset"])
    if eltype(tmp) <: Unitful.Current
      tmp = tmp .|> u"A"
    elseif eltype(tmp) <: Unitful.BField
      tmp = tmp .|> u"T"
    else
      error("The value for an offset has to be either given as a current or in tesla. You supplied the type `$(eltype(tmp))`.")
    end
    splattingDict[:offset] = tmp
  end

  splattingDict[:components] = Vector{ElectricalComponent}()
  components = [(k, v) for (k, v) in channelDict if v isa Dict]

  for (compId, component) in components
    divider = component["divider"]

    amplitude = uparse.(component["amplitude"])
    if eltype(amplitude) <: Unitful.Current
      amplitude = amplitude .|> u"A"
    elseif eltype(amplitude) <: Unitful.BField
      amplitude = amplitude .|> u"T"
    else
      error("The value for an amplitude has to be either given as a current or in tesla. You supplied the type `$(eltype(tmp))`.")
    end

    if haskey(component, "phase")
      phase = uparse.(component["phase"])
    else
      phase = fill(0.0u"rad", length(divider)) # Default phase
    end

    if haskey(component, "waveform")
      waveform = toWaveform(component["waveform"])
    else
      waveform = WAVEFORM_SINE # Default to sine
    end

    @assert length(amplitude) == length(phase) "The length of amplitude and phase must match."

    if divider isa Vector
      push!(splattingDict[:components],
            SweepElectricalComponent(divider=divider,
                                     amplitude=amplitude,
                                     waveform=waveform))
    else
      push!(splattingDict[:components],
            PeriodicElectricalComponent(id=compId,
                                        divider=divider,
                                        amplitude=amplitude,
                                        phase=phase,
                                        waveform=waveform))
    end
  end
  return PeriodicElectricalChannel(;splattingDict...)
end

export offset
offset(channel::PeriodicElectricalChannel) = channel.offset

export components
components(channel::PeriodicElectricalChannel) = channel.components

cycleDuration(channel::PeriodicElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = lcm([comp.divider for comp in components(channel)])/baseFrequency

export divider
divider(component::ElectricalComponent, trigger::Integer=1) = length(component.divider) == 1 ? component.divider[1] : component.divider[trigger]

export amplitude, amplitude!
amplitude(component::PeriodicElectricalComponent; period::Integer=1) = component.amplitude[period]
amplitude!(component::PeriodicElectricalComponent, value::Union{typeof(1.0u"T"),typeof(1.0u"V")}; period::Integer=1) = component.amplitude[period] = value
amplitude(component::SweepElectricalComponent; trigger::Integer=1) = component.amplitude[period]

export phase, phase!
phase(component::PeriodicElectricalComponent, trigger::Integer=1) = component.phase[trigger]
phase!(component::PeriodicElectricalComponent, value::typeof(1.0u"rad"); period::Integer=1) = component.phase[period] = value
phase(component::SweepElectricalComponent, trigger::Integer=1) = 0.0u"rad"

export waveform
waveform(component::ElectricalComponent) = component.waveform

export id
id(component::PeriodicElectricalComponent) = component.id