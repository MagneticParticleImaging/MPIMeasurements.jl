export MagneticField
"""
Description of a magnetic field.

The field can either be electromagnetically or mechanically changed.
The mechanical movement of e.g. an iron yoke would be defined within
two channels, one electrical and one mechanical.
"""
Base.@kwdef struct MagneticField
  "Unique ID of the field description."
  id::AbstractString
  "Transmit channels that are used for the field."
  channels::Vector{TxChannel}

  "Flag if the start of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeStartInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if a transition of the field should be convoluted.
  If the DAQ does not support this, it can may fall back
  to postponing the application of the settings.
  Not used for mechanical fields."
  safeTransitionInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the end of the field should be convoluted. In case of an existing brake on
  a mechanical channel this means a use of the brake."
  safeEndInterval::typeof(1.0u"s") = 0.5u"s"
  "Flag if the field should be convoluted down in case of an error. In case of an
  existing brake on a mechanical channel this means a use of the brake."
  safeErrorInterval::typeof(1.0u"s") = 0.5u"s"

  "Flag if the channels of the field should be controlled."
  control::Bool = true
  "Flag if the field should be decoupled. Not used for mechanical channels."
  decouple::Bool = true
end

# Indexing Interface
length(field::MagneticField) = length(channels(field))
function getindex(field::MagneticField, index::Integer)
  1 <= index <= length(field) || throw(BoundsError(channels(field), index))
  return channels(field)[index]
end
function getindex(field::MagneticField, index::String)
  for channel in field
    if id(channel) == index
      return channel
    end
  end
  throw(KeyError(index))
end
setindex!(field::MagneticField, txChannel::TxChannel, i::Integer) = channels(field)[i] = txChannel
firstindex(field::MagneticField) = start_(field)
lastindex(field::MagneticField) = length(field)
keys(field::MagneticField) = map(id, field)
haskey(field::MagneticField, key) = in(key, keys(field))

# Iterable Interface
start_(field::MagneticField) = 1
next_(field::MagneticField,state) = (field[state],state+1)
done_(field::MagneticField,state) = state > length(field)
iterate(field::MagneticField, s=start_(field)) = done_(field, s) ? nothing : next_(field, s)

push!(field::MagneticField, txChannel::TxChannel) = push!(channels(field), txChannel)
pop!(field::MagneticField) = pop!(channels(field))
empty!(field::MagneticField) = empty!(channels(field))
deleteat!(field::MagneticField, i) = deleteat!(channels(field), i)
function delete!(field::MagneticField, index::String)
  idx = findfirst(isequal(index), map(id, field))
  isnothing(idx) ? throw(KeyError(index)) : deleteat!(field, idx)
end


id(field::MagneticField) = field.id

export channels
channels(field::MagneticField) = field.channels
channels(field::MagneticField, T::Type{<:TxChannel}) = [channel for channel in channels(field) if typeof(channel) <: T]

export safeStartInterval
safeStartInterval(field::MagneticField) = field.safeStartInterval
export safeTransitionInterval
safeTransitionInterval(field::MagneticField) = field.safeTransitionInterval
export safeEndInterval
safeEndInterval(field::MagneticField) = field.safeEndInterval
export safeErrorInterval
safeErrorInterval(field::MagneticField) = field.safeErrorInterval

control(field::MagneticField) = field.control
decouple(field::MagneticField) = field.decouple

export electricalTxChannels
electricalTxChannels(field::MagneticField) = channels(field, ElectricalTxChannel)

export mechanicalTxChannels
mechanicalTxChannels(field::MagneticField) = channels(field, MechanicalTxChannel)

export periodicElectricalTxChannels
periodicElectricalTxChannels(field::MagneticField) = channels(field, PeriodicElectricalChannel)

export acyclicElectricalTxChannels
acyclicElectricalTxChannels(field::MagneticField) = channels(field, AcyclicElectricalTxChannel)

function toDict!(dict, field::MagneticField)
  for structField in [x for x in fieldnames(typeof(field)) if !in(x, [:id, :channels])]
    dict[String(structField)] = toDictValue(getproperty(field, structField))
  end
  for channel in channels(field)
    dict[id(channel)] = toDictValue(channel)
  end
  return dict
end

function toDict!(dict, fields::Vector{MagneticField})
  for field in fields
    dict[id(field)] = toDictValue(field)
  end
  return dict
end