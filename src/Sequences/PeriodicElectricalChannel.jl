# TODO: Can this type be removed in favor of ContinuousElectricalChannel?

export PeriodicElectricalComponent, SweepElectricalComponent, PeriodicElectricalChannel, ArbitraryElectricalComponent

"""
Component of an electrical channel with periodic base function.

$FIELDS
"""
Base.@kwdef mutable struct PeriodicElectricalComponent <: ElectricalComponent
  id::AbstractString
  "Divider of the component."
  divider::Rational{Int}
  "Amplitude (peak) of the component for each period of the field."
  amplitude::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"V")}, Vector{typeof(1.0u"A")}} # Is it really the right choice to have the periods here? Or should it be moved to the MagneticField?
  "Phase of the component for each period of the field."
  phase::Vector{typeof(1.0u"rad")}
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

"""
Sweepable component of an electrical channel with periodic base function.
Note: Does not allow for changes in phase since this would make the switch
between frequencies difficult.

$FIELDS
"""
Base.@kwdef mutable struct SweepElectricalComponent <: ElectricalComponent
  "Divider of the component."
  divider::Vector{Integer}
  "Amplitude (peak) of the channel for each divider in the sweep. Must have the same dimension as `divider`."
  amplitude::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"V")}}
  "Waveform of the component."
  waveform::Waveform = WAVEFORM_SINE
end

"""
Arbitrary waveform component of an electrical channel with periodic base function defined by a vector of $(RedPitayaDAQServer._awgBufferSize) values.

$FIELDS
"""
Base.@kwdef mutable struct ArbitraryElectricalComponent <: ElectricalComponent
  id::AbstractString
  "Divider of the component."
  divider::Rational{Int}
  "Amplitude scale of the base waveform for each period of the field"
  amplitude::Union{Vector{typeof(1.0u"T")}, Vector{typeof(1.0u"A")}, Vector{typeof(1.0u"V")}}
  "Phase of the component for each period of the field."
  phase::Vector{typeof(1.0u"rad")}
  "Values for the base waveform of the component, will be multiplied by `amplitude`"
  values::Vector{Float64}
end

"""
Electrical channel based on based on periodic base functions. Only the
PeriodicElectricalChannel counts for the cycle length calculation
  
$FIELDS
"""
Base.@kwdef mutable struct PeriodicElectricalChannel <: ElectricalTxChannel
  "ID corresponding to the channel configured in the scanner."
  id::AbstractString
  "Components added for this channel."
  components::Vector{ElectricalComponent}
  "Offset of the channel. If defined in Tesla, the calibration configured in the scanner will be used."
  offset::Union{typeof(1.0u"T"), typeof(1.0u"A"), typeof(1.0u"V")} = 0.0u"T"
  isDfChannel::Bool = true
  dcEnabled::Bool = true
end

unitIsTesla(chan::PeriodicElectricalChannel) = (dimension(offset(chan)) == dimension(u"T")) && all([dimension(amplitude(comp))==dimension(u"T") for comp in components(chan)])

# Indexing Interface
length(ch::PeriodicElectricalChannel) = length(components(ch))
function getindex(ch::PeriodicElectricalChannel, index::Integer)
  1 <= index <= length(ch) || throw(BoundsError(components(ch), index))
  return components(ch)[index]
end
function getindex(ch::PeriodicElectricalChannel, index::String)
  for channel in ch
    if id(channel) == index
      return channel
    end
  end
  throw(KeyError(index))
end
setindex!(ch::PeriodicElectricalChannel, comp::ElectricalComponent, i::Integer) = components(ch)[i] = comp
function setindex!(ch::PeriodicElectricalChannel, comp::ElectricalComponent, i::String)
  for (index, cmp) in enumerate(components(ch))
    if isequal(id(cmp), i)
      return setindex!(field, comp, index)
    end
  end
  push!(ch, comp)
end
firstindex(ch::PeriodicElectricalChannel) = start_(ch)
lastindex(ch::PeriodicElectricalChannel) = length(ch)
keys(ch::PeriodicElectricalChannel) = map(id, ch)
haskey(ch::PeriodicElectricalChannel, key) = in(key, keys(ch))

# Iterable Interface
start_(ch::PeriodicElectricalChannel) = 1
next_(ch::PeriodicElectricalChannel,state) = (ch[state],state+1)
done_(ch::PeriodicElectricalChannel,state) = state > length(ch)
iterate(ch::PeriodicElectricalChannel, s=start_(ch)) = done_(ch, s) ? nothing : next_(ch, s)

push!(ch::PeriodicElectricalChannel, comp::ElectricalComponent) = push!(components(ch), comp)
pop!(ch::PeriodicElectricalChannel) = pop!(components(ch))
empty!(ch::PeriodicElectricalChannel) = empty!(components(ch))
deleteat!(ch::PeriodicElectricalChannel, i) = deleteat!(components(ch), i)
function delete!(ch::PeriodicElectricalChannel, index::String)
  idx = findfirst(isequal(index), map(id, ch))
  isnothing(idx) ? throw(KeyError(index)) : deleteat!(ch, idx)
end


channeltype(::Type{<:PeriodicElectricalChannel}) = ContinuousTxChannel()

function createFieldChannel(channelID::AbstractString, ::Type{PeriodicElectricalChannel}, channelDict::Dict{String, Any})
  splattingDict = Dict{Symbol, Any}()
  splattingDict[:id] = channelID

  if haskey(channelDict, "offset")
    tmp = uparse.(channelDict["offset"])
    if eltype(tmp) <: Unitful.Current
      tmp = tmp .|> u"A"
    elseif eltype(tmp) <: Unitful.Voltage
      tmp = tmp .|> u"V"
    elseif eltype(tmp) <: Unitful.BField
      tmp = tmp .|> u"T"
    else
      error("The value for an offset has to be either given as a voltage, current or in tesla. You supplied the type `$(eltype(tmp))`.")
    end
    splattingDict[:offset] = tmp
  end

  if haskey(channelDict, "isDfChannel")
    splattingDict[:isDfChannel] = channelDict["isDfChannel"]
  end
  if haskey(channelDict, "dcEnabled")
    splattingDict[:dcEnabled] = channelDict["dcEnabled"]
  end

  components = Vector{ElectricalComponent}()
  componentsDict = [(k, v) for (k, v) in channelDict if v isa Dict]

  for (compId, component) in componentsDict
    push!(components, createChannelComponent(compId, component))
  end
  splattingDict[:components] = sort(components, by=id)
  return PeriodicElectricalChannel(;splattingDict...)
end

function createChannelComponent(componentID::AbstractString, componentDict::Dict{String, Any})
  if haskey(componentDict, "type")
    type = pop!(componentDict, "type")
    concreteType = getConcreteType(ElectricalComponent, type)
    if !isnothing(concreteType) 
      createChannelComponent(componentID, concreteType, componentDict)
    else
      error("Component $componentID has an unknown channel type `$type`.")
    end
  else
    error("Component $componentID has no `type` field.")
  end
end

function createChannelComponent(componentID::AbstractString, ::Type{PeriodicElectricalComponent}, componentDict::Dict{String, Any})

  divider, amplitude, phase = extractBasicComponentProperties(componentDict)

  if haskey(componentDict, "waveform")
    waveform = toWaveform(componentDict["waveform"])
  else
    waveform = WAVEFORM_SINE # Default to sine
  end

  return PeriodicElectricalComponent(id=componentID, divider=divider, amplitude=amplitude, phase=phase, waveform=waveform)
end

function createChannelComponent(componentID::AbstractString, ::Type{ArbitraryElectricalComponent}, componentDict::Dict{String, Any})
  
  divider, amplitude, phase = extractBasicComponentProperties(componentDict)

  if componentDict["values"] isa AbstractString # case 1: filename to waveform
    filename = joinpath(homedir(), ".mpi", "Waveforms", componentDict["values"])
    try
      values = reshape(h5read(filename, "/values"),:)
    catch 
      throw(SequenceConfigurationError("Could not load the waveform $(componentDict["values"]), either the file does not exist at $filename or the file structure is wrong"))
    end
  else # case 2: vector of real numbers
    values = componentDict["values"]
  end

  if abs(values[1]-values[end])>0.01 # more than 1% of max value in 1 of 2^14 samples -> slew > 160
    @warn "The first and last value of your selected waveform are producing a jump of size $(abs(values[1]-values[end]))! Please check your waveform, if this is intended!"
  end

  return ArbitraryElectricalComponent(id=componentID, divider=divider,amplitude=amplitude, phase=phase, values=values)
end

function extractBasicComponentProperties(componentDict::Dict{String, Any})
  divider = eval(Meta.parse("$(componentDict["divider"])"))
  if divider isa Dict; divider = divider["num"]//divider["den"] end
  if !(divider isa Rational); divider=rationalize(divider) end
  amplitude = uparse.(componentDict["amplitude"])
  if eltype(amplitude) <: Unitful.Current
    amplitude = amplitude .|> u"A"
  elseif eltype(amplitude) <: Unitful.Voltage
    amplitude = amplitude .|> u"V"
  elseif eltype(amplitude) <: Unitful.BField
    amplitude = amplitude .|> u"T"
  else
    error("The value for an amplitude has to be either given as a current or in tesla. You supplied the type `$(eltype(tmp))`.")
  end

  if haskey(componentDict, "phase")
    phaseDict = Dict("sine"=>0.0u"rad", "sin"=>0.0u"rad","cosine"=>pi/2u"rad", "cos"=>pi/2u"rad","-sine"=>pi*u"rad", "-sin"=>pi*u"rad","-cosine"=>-pi/2u"rad", "-cos"=>-pi/2u"rad")
    phase = []
    for x in componentDict["phase"]
      try
        push!(phase, uparse.(x))
      catch
        if haskey(phaseDict, x)
          push!(phase, phaseDict[x])
        else
          error("The value $x for the phase could not be parsed. Use either a unitful value, or one of the predefined keywords ($(keys(phaseDict)))")
        end
      end
    end
  else
    phase = fill(0.0u"rad", length(divider)) # Default phase
  end
  return divider, amplitude, phase
end

export offset, offset!
offset(channel::PeriodicElectricalChannel) = channel.offset
offset!(channel::PeriodicElectricalChannel, offset::Union{typeof(1.0u"T"),typeof(1.0u"V")}) = channel.offset = offset

export components
components(channel::PeriodicElectricalChannel) = channel.components
components(channel::PeriodicElectricalChannel, T::Type{<:ElectricalComponent}) = [component for component in components(channel) if typeof(component) <: T]
export periodicElectricalComponents
periodicElectricalComponents(channel::PeriodicElectricalChannel) = components(channel, PeriodicElectricalComponent)
export arbitraryElectricalComponents
arbitraryElectricalComponents(channel::PeriodicElectricalChannel) = components(channel, ArbitraryElectricalComponent)

cycleDuration(channel::PeriodicElectricalChannel, baseFrequency::typeof(1.0u"Hz")) = lcm([numerator(comp.divider) for comp in components(channel)])/baseFrequency

isDfChannel(channel::PeriodicElectricalChannel) = channel.isDfChannel

# TODO/JA: check if this can automatically be implemented for all setters (and getters)
function waveform!(channel::PeriodicElectricalChannel, componentId::AbstractString, value)
  index = findfirst(x -> id(x) == componentId, channel.components)
  if !isnothing(index)
    waveform!(channel.components[index], value)
  else
    throw(ArgumentError("Channel $(id(channel)) has no component with id $componentid"))
  end
end

export divider, divider!
divider(component::ElectricalComponent, trigger::Integer=1) = length(component.divider) == 1 ? component.divider[1] : component.divider[trigger]
divider!(component::PeriodicElectricalComponent,value::Union{Rational,Integer}) = component.divider = value

export amplitude, amplitude!
amplitude(component::Union{PeriodicElectricalComponent,ArbitraryElectricalComponent}; period::Integer=1) = component.amplitude[period]
function amplitude!(component::Union{PeriodicElectricalComponent,ArbitraryElectricalComponent}, value::Union{typeof(1.0u"T"),typeof(1.0u"V"),typeof(1.0u"A")}; period::Integer=1)
  if eltype(component.amplitude) != typeof(value) && length(component.amplitude) == 1
      component.amplitude = typeof(value)[value]
  else
    component.amplitude[period] = value
  end
end
amplitude(component::SweepElectricalComponent; trigger::Integer=1) = component.amplitude[period]

export phase, phase!
phase(component::Union{PeriodicElectricalComponent,ArbitraryElectricalComponent}, trigger::Integer=1) = component.phase[trigger]
phase!(component::Union{PeriodicElectricalComponent,ArbitraryElectricalComponent}, value::typeof(1.0u"rad"); period::Integer=1) = component.phase[period] = value
phase(component::SweepElectricalComponent, trigger::Integer=1) = 0.0u"rad"

export values, values!
values(component::ArbitraryElectricalComponent) = component.values
values!(component::ArbitraryElectricalComponent, values::Vector{Float64}) = component.values = values
scaledValues(component::ArbitraryElectricalComponent) = amplitude(component) .* circshift(values(component), -round(Int,phase(component)/(2π*u"rad")*length(values(component))))


export waveform, waveform!
waveform(component::ElectricalComponent) = component.waveform
waveform!(component::ElectricalComponent, value) = component.waveform = value
waveform(::ArbitraryElectricalComponent) = WAVEFORM_ARBITRARY
waveform!(::ArbitraryElectricalComponent, value) = error("Can not change the waveform type of an ArbitraryElectricalComponent. Use values!() to change the waveform.")

export id
id(component::PeriodicElectricalComponent) = component.id
id(component::ArbitraryElectricalComponent) = component.id

function toDict!(dict, component::ElectricalComponent)
  dict["type"] = string(typeof(component))
  for field in [x for x in fieldnames(typeof(component)) if !in(x, [:id])]
    dict[String(field)] = toDictValue(getproperty(component, field))
  end
  return dict
end

function toDict!(dict, channel::PeriodicElectricalChannel)
  dict["type"] = string(typeof(channel))
  for field in [x for x in fieldnames(typeof(channel)) if !in(x, [:id, :components])]
    dict[String(field)] = toDictValue(getproperty(channel, field))
  end
  for component in components(channel)
    dict[id(component)] = toDictValue(component)
  end
  return dict
end